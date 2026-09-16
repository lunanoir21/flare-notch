//! Cursor provider.
//!
//! As Codenotch reads it: the editor's own sign-in, kept in its VS Code-style
//! state database ~/.config/Cursor/User/globalStorage/state.vscdb
//! (`ItemTable`: `cursorAuth/accessToken` and `cursorAuth/stripeMembershipAuthId`,
//! joined into the cookie `WorkosCursorSessionToken=<authId>::<token>`), against
//!
//! ```text
//! GET https://cursor.com/api/usage-summary
//! ```
//!
//! `individualUsage.plan.totalPercentUsed` is the dashboard's "Included usage",
//! and 0 is a reading, not a gap. API usage is listed when above zero, on-demand
//! when it has a real limit; all three reset at `billingCycleEnd`.
//!
//! The database is opened read-only (`mode=ro`, then `immutable=1` once the
//! editor has exited and taken its -shm with it) and never written. Cursor
//! keeps no usage on disk, so local mode has nothing to show for it.

use std::path::Path;

use anyhow::Result;
use rusqlite::types::ValueRef;
use rusqlite::{Connection, OpenFlags};
use serde_json::Value;

use crate::config::{Consent, DataMode};
use crate::http::{self, HttpError};
use crate::store::Saved;
use crate::{Config, Fetch, ProviderUsage, SOURCE_LOCAL, SOURCE_OFFICIAL, Status, UsageProvider, UsageWindow, paths};

const ID: &str = "cursor";
const ENDPOINT: &str = "https://cursor.com/api/usage-summary";
const POLL_SECS: i64 = 300;

pub struct Cursor {
    config: Config,
}

impl Cursor {
    pub fn new(config: Config) -> Self {
        Self { config }
    }
}

impl UsageProvider for Cursor {
    fn id(&self) -> &'static str {
        ID
    }

    fn fetch(&self, ctx: &Fetch) -> Result<ProviderUsage> {
        let db = paths::cursor_state_db()?;
        if !db.is_file() {
            return Ok(ProviderUsage::absent(ID));
        }
        if self.config.data.mode == DataMode::Local {
            let mut usage = ProviderUsage::new(ID, SOURCE_LOCAL);
            usage.note = Some("Cursor keeps no usage on disk — set data.mode to official to read it".into());
            return Ok(usage);
        }
        if self.config.data.cursor_consent != Consent::Granted {
            let mut usage = ProviderUsage::new(ID, SOURCE_LOCAL);
            usage.status = Status::NeedsConsent;
            usage.note = Some(
                "Official mode would read Cursor's live session from the editor's own state \
                 and send it to cursor.com — needs a one-time yes first"
                    .into(),
            );
            return Ok(usage);
        }

        let mut saved = Saved::load(ID);
        let mut usage = saved
            .usage
            .clone()
            .unwrap_or_else(|| ProviderUsage::new(ID, SOURCE_OFFICIAL));
        if saved.due(ctx.now, POLL_SECS, ctx.force) {
            saved.last_attempt = Some(ctx.now);
            read_live(&db, ctx.now, &mut usage);
            saved.usage = Some(usage.clone());
            saved.save(ID);
        }
        usage.settle(ctx.now);
        Ok(usage)
    }
}

fn read_live(db: &Path, now: i64, usage: &mut ProviderUsage) {
    // Re-read every time: the editor rotates the token.
    let Some(credentials) = read_credentials(db) else {
        usage.status = Status::NeedsAuth;
        usage.note = Some("Sign in to Cursor (the editor) to see usage".into());
        return;
    };
    let reply = http::get_json(
        ENDPOINT,
        &[("Cookie", credentials.cookie.as_str()), ("Accept", "application/json")],
    );
    match reply {
        Ok(reply) => {
            let (windows, why) = parse_summary(&reply);
            usage.source = SOURCE_OFFICIAL.into();
            usage.fetched_at = Some(now);
            usage.plan = reply
                .get("membershipType")
                .and_then(Value::as_str)
                .map(str::to_string)
                .or(credentials.plan);
            if windows.is_empty() {
                usage.status = Status::None;
                usage.windows.clear();
                usage.headline = None;
                usage.note = Some(why);
            } else {
                usage.status = Status::Ok;
                usage.headline = windows
                    .iter()
                    .find(|w| w.id == "included")
                    .or(windows.first())
                    .map(|w| w.id.clone());
                usage.windows = windows;
                usage.note = None;
            }
        }
        Err(HttpError::Status { code: 401 | 403, .. }) => {
            usage.status = Status::NeedsAuth;
            usage.note = Some("Cursor session was rejected — sign in again in the editor".into());
        }
        Err(err) => {
            // Stale beats invented: the old reading stays, marked.
            usage.status = if usage.windows.is_empty() { Status::Error } else { Status::Stale };
            usage.note = Some(err.to_string());
        }
    }
}

fn pct(value: Option<&Value>) -> Option<f64> {
    value.and_then(Value::as_f64).filter(|p| p.is_finite())
}

/// usage-summary → windows, and a reason when there are none.
fn parse_summary(reply: &Value) -> (Vec<UsageWindow>, String) {
    let resets_at = reply
        .get("billingCycleEnd")
        .and_then(Value::as_str)
        .and_then(crate::time::rfc3339_to_unix);
    let usage = reply.get("individualUsage");
    let plan = usage.and_then(|u| u.get("plan"));
    let mut out = Vec::new();

    if let Some(total) = pct(plan.and_then(|p| p.get("totalPercentUsed"))) {
        out.push(UsageWindow::new("included", "Included usage", total, None, resets_at));
    }
    if let Some(api) = pct(plan.and_then(|p| p.get("apiPercentUsed"))).filter(|p| *p > 0.0) {
        out.push(UsageWindow::new("api", "API usage", api, None, resets_at));
    }
    if let Some(on_demand) = usage.and_then(|u| u.get("onDemand")) {
        let enabled = on_demand.get("enabled").and_then(Value::as_bool).unwrap_or(false);
        let limit = on_demand.get("limit").and_then(Value::as_f64).unwrap_or(0.0);
        if let Some(used) = on_demand.get("used").and_then(Value::as_f64) {
            if enabled && limit > 0.0 {
                out.push(UsageWindow::new("on_demand", "On demand", used / limit * 100.0, None, resets_at));
            }
        }
    }

    let membership = reply.get("membershipType").and_then(Value::as_str).unwrap_or("this");
    let why = if reply.get("isUnlimited").and_then(Value::as_bool) == Some(true) {
        format!("Unlimited on the {membership} plan — nothing to meter")
    } else {
        format!("The {membership} plan has nothing for Cursor to meter yet")
    };
    (out, why)
}

struct Credentials {
    cookie: String,
    plan: Option<String>,
}

fn read_credentials(db: &Path) -> Option<Credentials> {
    let conn = open_read_only(db)?;
    let token = item(&conn, "cursorAuth/accessToken")?;
    let auth_id = item(&conn, "cursorAuth/stripeMembershipAuthId")?;
    Some(Credentials {
        cookie: format!("WorkosCursorSessionToken={auth_id}::{token}"),
        plan: item(&conn, "cursorAuth/stripeMembershipType"),
    })
}

fn open_read_only(path: &Path) -> Option<Connection> {
    let flags = OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX;
    if let Ok(conn) = Connection::open_with_flags(path, flags) {
        // With the -shm gone, opening can succeed and the first query fail.
        match conn.query_row("SELECT 1 FROM ItemTable LIMIT 1", [], |_| Ok(())) {
            Ok(()) | Err(rusqlite::Error::QueryReturnedNoRows) => return Some(conn),
            Err(_) => {}
        }
    }
    let encoded = path
        .to_string_lossy()
        .replace('%', "%25")
        .replace('#', "%23")
        .replace('?', "%3F");
    Connection::open_with_flags(
        format!("file:{encoded}?immutable=1"),
        flags | OpenFlags::SQLITE_OPEN_URI,
    )
    .ok()
}

fn item(conn: &Connection, key: &str) -> Option<String> {
    conn.query_row("SELECT value FROM ItemTable WHERE key = ?1", [key], |row| {
        Ok(match row.get_ref(0)? {
            ValueRef::Text(bytes) | ValueRef::Blob(bytes) => String::from_utf8(bytes.to_vec()).ok(),
            _ => None,
        })
    })
    .ok()
    .flatten()
    .map(|value| value.trim().to_string())
    .filter(|value| !value.is_empty())
}

/// For `flare doctor`. Never prints a secret.
pub fn probe() -> Vec<String> {
    let Ok(db) = paths::cursor_state_db() else {
        return vec!["state database: unresolved".into()];
    };
    if !db.is_file() {
        return vec![format!("state database: NOT FOUND ({}) — not installed", db.display())];
    }
    vec![match read_credentials(&db) {
        Some(credentials) => format!(
            "session: borrowed from the editor (cookie {} chars, plan {})",
            credentials.cookie.len(),
            credentials.plan.as_deref().unwrap_or("unknown")
        ),
        None => format!("session: none in {} (editor not signed in?)", db.display()),
    }]
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn included_usage_is_a_reading_even_at_zero() {
        let (windows, _) = parse_summary(&json!({
            "billingCycleEnd": "2026-10-01T00:00:00.000Z",
            "membershipType": "free",
            "individualUsage": {"plan": {"totalPercentUsed": 0, "apiPercentUsed": 0, "used": 0, "limit": 0}}
        }));
        assert_eq!(windows.len(), 1);
        assert_eq!(windows[0].id, "included");
        assert_eq!(windows[0].used, 0.0);
        assert!(windows[0].resets_at.is_some());
    }

    #[test]
    fn api_and_on_demand_join_when_they_mean_something() {
        let (windows, _) = parse_summary(&json!({
            "individualUsage": {
                "plan": {"totalPercentUsed": 21.5, "apiPercentUsed": 4},
                "onDemand": {"enabled": true, "used": 5, "limit": 20}}
        }));
        let ids: Vec<&str> = windows.iter().map(|w| w.id.as_str()).collect();
        assert_eq!(ids, ["included", "api", "on_demand"]);
        assert!((windows[2].used - 0.25).abs() < 1e-9);
    }

    #[test]
    fn nothing_metered_says_why() {
        let (windows, why) = parse_summary(&json!({"membershipType": "pro", "isUnlimited": true}));
        assert!(windows.is_empty());
        assert!(why.contains("Unlimited"));
    }

    #[test]
    fn borrows_the_editor_session_from_its_state_database() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("state.vscdb");
        let conn = Connection::open(&path).unwrap();
        conn.execute_batch(
            "CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
             INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', 'tok');
             INSERT INTO ItemTable VALUES ('cursorAuth/stripeMembershipAuthId', 'user_1');
             INSERT INTO ItemTable VALUES ('cursorAuth/stripeMembershipType', 'pro');",
        )
        .unwrap();
        drop(conn);
        let credentials = read_credentials(&path).expect("credentials");
        assert_eq!(credentials.cookie, "WorkosCursorSessionToken=user_1::tok");
        assert_eq!(credentials.plan.as_deref(), Some("pro"));
    }
}
