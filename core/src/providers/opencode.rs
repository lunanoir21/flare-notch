//! OpenCode provider (local in both modes).
//!
//! Usage lives in the sqlite database OpenCode keeps at
//! $XDG_DATA_HOME/opencode/opencode.db. Its `session` table already carries
//! per-session totals, so flare aggregates those columns instead of
//! re-deriving them from the message log. The totals were checked against
//! `opencode stats --days 1` on a real database and match exactly.
//!
//! OpenCode authenticates with the user's own provider API keys rather than a
//! subscription, so there is no rate-limit window to report: `metered` is
//! false and the widget shows today's tokens instead of a percentage.

use anyhow::Result;
use rusqlite::{Connection, OpenFlags};

use crate::{Config, Fetch, ProviderUsage, SOURCE_LOCAL, Status, UsageProvider, err_parse, paths};

const ID: &str = "opencode";

pub struct OpenCode {
    config: Config,
}

impl OpenCode {
    pub fn new(config: Config) -> Self {
        Self { config }
    }
}

struct Totals {
    cost_usd: f64,
    tokens: u64,
}

impl UsageProvider for OpenCode {
    fn id(&self) -> &'static str {
        ID
    }

    fn fetch(&self, _ctx: &Fetch) -> Result<ProviderUsage> {
        let data_dir = paths::opencode_data()?;
        let db_path = data_dir.join("opencode.db");
        if !db_path.exists() {
            return Ok(ProviderUsage::absent(ID));
        }

        let mut usage = ProviderUsage::new(ID, SOURCE_LOCAL);
        usage.metered = false;
        usage.status = Status::Ok;
        usage.account = read_account(&data_dir.join("auth.json"));

        match read_totals(&db_path, self.config.scan_cutoff_secs()) {
            Ok(totals) => {
                usage.cost_today_usd = Some(totals.cost_usd);
                usage.tokens_today = Some(totals.tokens);
            }
            Err(err) => {
                usage.status = Status::Error;
                usage.error = Some(err_parse(format!("{err:#}")));
            }
        }
        Ok(usage)
    }
}

/// Sum the session totals updated at or after `cutoff_secs`.
///
/// `time_updated` is epoch milliseconds. `tokens_reasoning` is left out: it
/// may already be counted inside the output total.
fn read_totals(db_path: &std::path::Path, cutoff_secs: i64) -> Result<Totals> {
    let uri = format!("file:{}?mode=ro", db_path.display());
    let conn = Connection::open_with_flags(
        &uri,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_URI,
    )?;

    let cutoff_millis = cutoff_secs.saturating_mul(1000);
    let (cost, input, output, cache_read, cache_write) = conn.query_row(
        "SELECT \
           coalesce(sum(cost), 0.0), \
           coalesce(sum(tokens_input), 0), \
           coalesce(sum(tokens_output), 0), \
           coalesce(sum(tokens_cache_read), 0), \
           coalesce(sum(tokens_cache_write), 0) \
         FROM session WHERE time_updated >= ?1",
        [cutoff_millis],
        |row| {
            Ok((
                row.get::<_, f64>(0)?,
                row.get::<_, i64>(1)?,
                row.get::<_, i64>(2)?,
                row.get::<_, i64>(3)?,
                row.get::<_, i64>(4)?,
            ))
        },
    )?;

    let tokens = [input, output, cache_read, cache_write]
        .into_iter()
        .map(|value| u64::try_from(value).unwrap_or_default())
        .sum();

    Ok(Totals { cost_usd: cost, tokens })
}

/// Only the provider names in auth.json are read, never the credentials.
fn read_account(auth_path: &std::path::Path) -> Option<String> {
    let text = std::fs::read_to_string(auth_path).ok()?;
    let value: serde_json::Value = serde_json::from_str(&text).ok()?;
    let mut names: Vec<&str> = value.as_object()?.keys().map(String::as_str).collect();
    if names.is_empty() {
        return None;
    }
    names.sort_unstable();
    Some(names.join(", "))
}

/// For `flare doctor`.
pub fn probe() -> Vec<String> {
    match paths::opencode_data() {
        Ok(dir) => {
            let db = dir.join("opencode.db");
            let wal = dir.join("opencode.db-wal");
            match [paths::mtime_secs(&db), paths::mtime_secs(&wal)].into_iter().flatten().max() {
                Some(at) => vec![format!(
                    "database: found ({}), last written {}s ago",
                    db.display(),
                    paths::now_secs() - at
                )],
                None => vec![format!("database: NOT FOUND ({}) — not installed", db.display())],
            }
        }
        Err(err) => vec![format!("data dir: unresolved ({err:#})")],
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::{NO_CUTOFF, fixture};

    fn seeded_db(dir: &std::path::Path) -> std::path::PathBuf {
        let path = dir.join("opencode.db");
        let conn = Connection::open(&path).expect("create test database");
        conn.execute_batch(
            "CREATE TABLE session (
                 id text PRIMARY KEY,
                 cost real DEFAULT 0 NOT NULL,
                 tokens_input integer DEFAULT 0 NOT NULL,
                 tokens_output integer DEFAULT 0 NOT NULL,
                 tokens_reasoning integer DEFAULT 0 NOT NULL,
                 tokens_cache_read integer DEFAULT 0 NOT NULL,
                 tokens_cache_write integer DEFAULT 0 NOT NULL,
                 time_updated integer NOT NULL
             );
             INSERT INTO session VALUES ('a', 1.5, 100, 20, 7, 300, 40, 2000000000000);
             INSERT INTO session VALUES ('b', 0.25, 10, 2, 1, 30, 4, 2000000000000);
             INSERT INTO session VALUES ('old', 99.0, 999, 999, 999, 999, 999, 1000);",
        )
        .expect("seed test database");
        path
    }

    #[test]
    fn sums_the_columns_opencode_stats_itself_reports() {
        let dir = tempfile::tempdir().expect("temp dir");
        let totals = read_totals(&seeded_db(dir.path()), NO_CUTOFF).expect("totals");
        assert_eq!(totals.tokens, 4502);
        assert!((totals.cost_usd - 100.75).abs() < 1e-9);
    }

    #[test]
    fn honors_the_scan_window() {
        let dir = tempfile::tempdir().expect("temp dir");
        let totals = read_totals(&seeded_db(dir.path()), 1_900_000_000).expect("totals");
        assert_eq!(totals.tokens, 506);
        assert!((totals.cost_usd - 1.75).abs() < 1e-9);
    }

    #[test]
    fn a_database_with_an_unexpected_schema_errors_rather_than_panics() {
        let dir = tempfile::tempdir().expect("temp dir");
        let path = dir.path().join("opencode.db");
        let conn = Connection::open(&path).expect("create test database");
        conn.execute_batch("CREATE TABLE unrelated (x integer);").expect("seed");
        assert!(read_totals(&path, NO_CUTOFF).is_err());
    }

    #[test]
    fn labels_the_account_from_the_provider_names_in_auth() {
        let account = read_account(&fixture("opencode/auth_ok.json"));
        assert_eq!(account.as_deref(), Some("nvidia, openrouter"));
        assert!(read_account(&fixture("opencode/no_such_auth.json")).is_none());
    }
}
