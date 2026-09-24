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

use std::path::Path;

use anyhow::Result;
use rusqlite::{Connection, OpenFlags, OptionalExtension};

use crate::sessions::{self, Logged, Session, SessionState};
use crate::{Activity, Config, Fetch, ModelUse, ProviderUsage, SOURCE_LOCAL, Status, Unit, UsageProvider, err_parse, paths};

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
    fn id(&self) -> &str {
        ID
    }

    fn probe(&self) -> Vec<String> {
        probe()
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

    fn activity(&self, cutoff_secs: i64) -> Option<Activity> {
        let db = paths::opencode_data().ok()?.join("opencode.db");
        read_hours(&db, cutoff_secs).ok()
    }

    fn session_log(&self, now: i64) -> Option<Vec<Logged>> {
        let db = paths::opencode_data().ok()?.join("opencode.db");
        read_sessions(&db, now - sessions::LOG_KEEP_SECS, now).ok()
    }

    fn open_sessions(&self) -> Vec<Session> {
        let Ok(db) = paths::opencode_data().map(|dir| dir.join("opencode.db")) else {
            return Vec::new();
        };
        open_sessions_at(&db, Path::new("/proc")).unwrap_or_default()
    }
}

/// OpenCode keeps no per-session pid record the way Claude Code does, so a
/// session only counts as open while its own `opencode` process is still
/// running. Its cwd finds the session it most recently touched in the
/// database, for a name; with no status field to read, every match is idle.
fn open_sessions_at(db_path: &Path, proc_root: &Path) -> Result<Vec<Session>> {
    let processes = sessions::processes_named(proc_root, "opencode", &["serve"]);
    if processes.is_empty() {
        return Ok(Vec::new());
    }
    let conn = open(db_path)?;
    let mut statement = conn.prepare(
        "SELECT title, time_created FROM session \
         WHERE parent_id IS NULL AND directory = ?1 \
         ORDER BY time_updated DESC LIMIT 1",
    )?;
    let mut out: Vec<Session> = processes
        .into_iter()
        .map(|(pid, cwd)| {
            let directory = cwd.to_string_lossy().into_owned();
            let project = sessions::folder_name(&directory);
            let row: Option<(String, i64)> = statement
                .query_row([&directory], |row| Ok((row.get(0)?, row.get(1)?)))
                .optional()
                .unwrap_or(None);
            let (name, started_at) = match row {
                Some((title, created)) if !title.trim().is_empty() => (title, Some(created / 1000)),
                Some((_, created)) => (project.clone(), Some(created / 1000)),
                None => (project.clone(), None),
            };
            Session { pid, name, project, state: SessionState::Idle, waiting_for: None, started_at }
        })
        .collect();
    out.sort_by_key(|session| (session.started_at, session.pid));
    Ok(out)
}

fn open(db_path: &Path) -> Result<Connection> {
    let uri = format!("file:{}?mode=ro", db_path.display());
    Ok(Connection::open_with_flags(
        &uri,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_URI,
    )?)
}

/// Tokens and replies per hour, from each assistant message's own counts,
/// which add up to the session totals `read_totals` sums. Only sessions
/// touched since the cutoff are joined, so the message table is reached
/// through its session index rather than scanned whole.
fn read_hours(db_path: &Path, cutoff_secs: i64) -> Result<Activity> {
    let conn = open(db_path)?;
    let cutoff_millis = cutoff_secs.saturating_mul(1000);
    let mut statement = conn.prepare(
        "SELECT (m.time_created / 1000) - (m.time_created / 1000) % 3600 AS hour, \
           sum(coalesce(json_extract(m.data, '$.tokens.input'), 0) \
             + coalesce(json_extract(m.data, '$.tokens.output'), 0) \
             + coalesce(json_extract(m.data, '$.tokens.cache.read'), 0) \
             + coalesce(json_extract(m.data, '$.tokens.cache.write'), 0)), \
           count(*) \
         FROM session s JOIN message m ON m.session_id = s.id \
         WHERE s.time_updated >= ?1 AND m.time_created >= ?1 \
           AND json_extract(m.data, '$.role') = 'assistant' \
         GROUP BY hour ORDER BY hour",
    )?;
    let hours = statement
        .query_map([cutoff_millis], |row| {
            Ok((row.get::<_, i64>(0)?, row.get::<_, f64>(1)?, row.get::<_, u32>(2)?))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;

    let mut statement = conn.prepare(
        "SELECT json_extract(m.data, '$.modelID') AS model_id, \
           sum(coalesce(json_extract(m.data, '$.tokens.input'), 0) \
             + coalesce(json_extract(m.data, '$.tokens.output'), 0) \
             + coalesce(json_extract(m.data, '$.tokens.cache.read'), 0) \
             + coalesce(json_extract(m.data, '$.tokens.cache.write'), 0)) AS tokens, \
           count(*) \
         FROM session s JOIN message m ON m.session_id = s.id \
         WHERE s.time_updated >= ?1 AND m.time_created >= ?1 \
           AND json_extract(m.data, '$.role') = 'assistant' AND model_id IS NOT NULL \
         GROUP BY model_id ORDER BY tokens DESC",
    )?;
    let models = statement
        .query_map([cutoff_millis], |row| {
            Ok(ModelUse { model: row.get(0)?, amount: row.get(1)?, replies: row.get(2)? })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(Activity { unit: Unit::Tokens, hours, models })
}

/// Top-level sessions touched since `since_secs`; a subagent's session has a
/// parent and is part of the one that started it.
fn read_sessions(db_path: &Path, since_secs: i64, now: i64) -> Result<Vec<Logged>> {
    let conn = open(db_path)?;
    let mut statement = conn.prepare(
        "SELECT title, directory, time_created, time_updated FROM session \
         WHERE parent_id IS NULL AND time_updated >= ?1 ORDER BY time_created",
    )?;
    let log = statement
        .query_map([since_secs.saturating_mul(1000)], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?, row.get::<_, i64>(2)?, row.get::<_, i64>(3)?))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?
        .into_iter()
        .map(|(title, directory, created, updated)| {
            Logged::from_history(title, sessions::folder_name(&directory), created / 1000, updated / 1000, now)
        })
        .collect();
    Ok(log)
}

/// Sum the session totals updated at or after `cutoff_secs`.
///
/// `time_updated` is epoch milliseconds. `tokens_reasoning` is left out: it
/// may already be counted inside the output total.
fn read_totals(db_path: &Path, cutoff_secs: i64) -> Result<Totals> {
    let conn = open(db_path)?;
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
fn read_account(auth_path: &Path) -> Option<String> {
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

    /// Two sessions, one a subagent of the other, and their messages.
    fn seeded_history(dir: &Path) -> std::path::PathBuf {
        let path = dir.join("opencode.db");
        let conn = Connection::open(&path).expect("create test database");
        conn.execute_batch(
            r#"CREATE TABLE session (
                   id text PRIMARY KEY, parent_id text, title text NOT NULL,
                   directory text NOT NULL, time_created integer NOT NULL,
                   time_updated integer NOT NULL
               );
               CREATE TABLE message (
                   id text PRIMARY KEY, session_id text NOT NULL,
                   time_created integer NOT NULL, data text NOT NULL
               );
               INSERT INTO session VALUES ('a', NULL, 'fix the parser', '/home/u/flare', 3600000, 7300000);
               INSERT INTO session VALUES ('sub', 'a', 'explore', '/home/u/flare', 3700000, 3800000);
               INSERT INTO message VALUES ('1', 'a', 3600000, '{"role":"user"}');
               INSERT INTO message VALUES ('2', 'a', 3700000,
                   '{"role":"assistant","modelID":"big","tokens":{"input":10,"output":5,"reasoning":3,"cache":{"read":100,"write":1}}}');
               INSERT INTO message VALUES ('3', 'sub', 3800000,
                   '{"role":"assistant","modelID":"small","tokens":{"input":1,"output":1,"cache":{"read":0,"write":0}}}');
               INSERT INTO message VALUES ('4', 'a', 7300000,
                   '{"role":"assistant","modelID":"small","tokens":{"input":2,"output":2}}');"#,
        )
        .expect("seed test database");
        path
    }

    #[test]
    fn hours_sum_each_assistant_reply_once() {
        let dir = tempfile::tempdir().expect("temp dir");
        let activity = read_hours(&seeded_history(dir.path()), NO_CUTOFF).expect("hours");
        assert_eq!(activity.unit, Unit::Tokens);
        assert_eq!(activity.hours, vec![(3600, 118.0, 2), (7200, 4.0, 1)]);
        assert_eq!(
            activity.models,
            vec![
                ModelUse { model: "big".into(), amount: 116.0, replies: 1 },
                ModelUse { model: "small".into(), amount: 6.0, replies: 2 },
            ]
        );
    }

    #[test]
    fn the_session_log_leaves_out_subagents() {
        let dir = tempfile::tempdir().expect("temp dir");
        let db = seeded_history(dir.path());
        let log = read_sessions(&db, NO_CUTOFF, 7300).expect("sessions");
        assert_eq!(log.len(), 1);
        assert_eq!(log[0].name, "fix the parser");
        assert_eq!(log[0].project, "flare");
        assert_eq!((log[0].started_at, log[0].last_seen), (3600, 7300));
        assert!(!log[0].ended);
        let later = read_sessions(&db, NO_CUTOFF, 7300 + 3600).expect("sessions");
        assert!(later[0].ended);
    }

    #[test]
    fn labels_the_account_from_the_provider_names_in_auth() {
        let account = read_account(&fixture("opencode/auth_ok.json"));
        assert_eq!(account.as_deref(), Some("nvidia, openrouter"));
        assert!(read_account(&fixture("opencode/no_such_auth.json")).is_none());
    }

    fn write_proc(proc_root: &Path, pid: u32, args: &[&str], cwd: &Path) {
        let dir = proc_root.join(pid.to_string());
        std::fs::create_dir_all(&dir).expect("proc dir");
        std::fs::write(dir.join("cmdline"), args.join("\0") + "\0").expect("cmdline");
        std::os::unix::fs::symlink(cwd, dir.join("cwd")).expect("cwd symlink");
    }

    #[test]
    fn a_running_process_is_a_session_named_after_its_latest_db_row() {
        let dir = tempfile::tempdir().expect("temp dir");
        let db = seeded_history(dir.path());
        let proc_root = dir.path().join("proc");
        write_proc(&proc_root, 42, &["/usr/bin/opencode", "run", "hi"], Path::new("/home/u/flare"));

        let sessions = open_sessions_at(&db, &proc_root).expect("sessions");
        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].pid, 42);
        assert_eq!(sessions[0].name, "fix the parser");
        assert_eq!(sessions[0].project, "flare");
        assert_eq!(sessions[0].state, SessionState::Idle);
    }

    #[test]
    fn a_background_serve_process_is_not_a_session() {
        let dir = tempfile::tempdir().expect("temp dir");
        let db = seeded_history(dir.path());
        let proc_root = dir.path().join("proc");
        write_proc(&proc_root, 7, &["/usr/bin/opencode", "serve", "--port", "0"], Path::new("/home/u/flare"));

        assert!(open_sessions_at(&db, &proc_root).expect("sessions").is_empty());
    }

    #[test]
    fn a_process_with_no_matching_db_row_still_shows_up_by_its_folder() {
        let dir = tempfile::tempdir().expect("temp dir");
        let db = seeded_history(dir.path());
        let proc_root = dir.path().join("proc");
        write_proc(&proc_root, 9, &["/usr/bin/opencode", "run", "hi"], Path::new("/home/u/other"));

        let sessions = open_sessions_at(&db, &proc_root).expect("sessions");
        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].name, "other");
        assert_eq!(sessions[0].project, "other");
        assert_eq!(sessions[0].started_at, None);
    }
}
