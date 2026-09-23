//! Kiro CLI (`kiro-cli`) provider.
//!
//! Official mode reads the plan's monthly credits the way kiro-cli itself
//! does, with the sign-in it keeps in $XDG_DATA_HOME/kiro-cli/data.sqlite3
//! (`auth_kv`, a `kirocli:*:token` row):
//!
//! ```text
//! GET https://q.<region>.amazonaws.com/getUsageLimits
//!     ?origin=KIRO_CLI&profileArn=<arn>&resourceType=AGENTIC_REQUEST&isEmailRequired=false
//! Authorization: Bearer <access_token>
//! ```
//!
//! `usageBreakdownList[resourceType = CREDIT]` carries
//! `currentUsageWithPrecision`, `usageLimitWithPrecision` and `nextDateReset`
//! (unix seconds); an ACTIVE `freeTrialInfo` adds its own usage and limit.
//! The shape was taken from a real reply. The token lives an hour; shortly
//! before it runs out `kiro-cli whoami` is run, which renews it. Nothing here
//! writes the database.
//!
//! In both modes, kiro-cli writes every chat session to ~/.kiro/sessions/cli/<id>.json and
//! rewrites it as the session goes on. Each finished turn lists what it was
//! metered, in credits, one entry per model request:
//!
//! ```text
//! session_state.conversation_metadata.user_turn_metadatas[]
//!   .end_timestamp     RFC 3339
//!   .metering_usage[]  { "value": 0.17, "unit": "credit" }
//! ```
//!
//! The token counts beside them are written as zero, so Kiro is shown in
//! credits. Local mode has no allowance to measure against: it shows today's
//! credits instead of a percentage.

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use anyhow::Result;
use rusqlite::{Connection, OpenFlags, OptionalExtension};
use serde::Deserialize;
use serde_json::Value;

use crate::config::{Binary, DataMode};
use crate::http::{self, HttpError};
use crate::sessions::{self, Logged};
use crate::store::{self, Saved};
use crate::{
    Activity, Amount, Config, Reply, Fetch, ProviderUsage, SOURCE_LOCAL, SOURCE_OFFICIAL, Status, Unit,
    UsageProvider, UsageWindow, err_parse, paths, time,
};

const ID: &str = "kiro";
/// Credits move slowly and the endpoint is shared with kiro-cli itself.
const POLL_SECS: i64 = 300;
const RENEW_MARGIN_SECS: i64 = 5 * 60;
const RENEW_COOLDOWN_SECS: i64 = 10 * 60;
const RENEW_TIMEOUT: Duration = Duration::from_secs(30);
const EXPIRED_NOTE: &str = "Kiro sign-in expired — run kiro-cli once to renew it";
const WINDOW_ID: &str = "monthly_credits";

pub struct Kiro {
    config: Config,
}

impl Kiro {
    pub fn new(config: Config) -> Self {
        Self { config }
    }
}

fn sessions_dir() -> Result<PathBuf> {
    Ok(paths::kiro_home()?.join("sessions").join("cli"))
}

impl UsageProvider for Kiro {
    fn id(&self) -> &str {
        ID
    }

    fn probe(&self) -> Vec<String> {
        probe()
    }

    fn fetch(&self, ctx: &Fetch) -> Result<ProviderUsage> {
        let dir = sessions_dir()?;
        if !dir.exists() && !data_db()?.exists() {
            return Ok(ProviderUsage::absent(ID));
        }

        let mut usage = match self.config.data.mode {
            DataMode::Official => official(ctx, &self.config.kiro),
            DataMode::Local => local(),
        };

        let cutoff = self.config.scan_cutoff_secs();
        let scan = scan(&dir, cutoff);
        usage.credits_today = Some(
            scan.sessions
                .iter()
                .flat_map(|s| &s.requests)
                .filter(|(at, _)| *at >= cutoff)
                .fold(0.0, |total, (_, credits)| total + credits),
        );
        usage.error = scan.error.map(err_parse);
        usage.settle(ctx.now);
        Ok(usage)
    }

    fn activity(&self, cutoff_secs: i64) -> Option<Activity> {
        let requests = scan(&sessions_dir().ok()?, cutoff_secs).sessions.into_iter().flat_map(|s| {
            let model = s.model;
            s.requests.into_iter().map(move |(at, amount)| Reply { at, amount, model: model.clone() })
        });
        Some(Activity::from_replies(Unit::Credits, requests.filter(|r| r.at >= cutoff_secs)))
    }

    fn session_log(&self, now: i64) -> Option<Vec<Logged>> {
        let since = now - sessions::LOG_KEEP_SECS;
        let mut log: Vec<Logged> = scan(&sessions_dir().ok()?, since)
            .sessions
            .into_iter()
            .filter(|s| s.last_seen >= since)
            .map(|s| Logged::from_history(s.title, s.project, s.started_at, s.last_seen, now))
            .collect();
        log.sort_by_key(|entry| entry.started_at);
        Some(log)
    }
}

fn local() -> ProviderUsage {
    let mut usage = ProviderUsage::new(ID, SOURCE_LOCAL);
    usage.metered = false;
    usage.status = Status::Ok;
    usage
}

fn data_db() -> Result<PathBuf> {
    Ok(paths::data_dir()?.join("kiro-cli").join("data.sqlite3"))
}

// ---------------- official ----------------

fn official(ctx: &Fetch, kiro_bin: &Binary) -> ProviderUsage {
    let now = ctx.now;
    let mut saved = Saved::load(ID);
    let mut usage = saved
        .usage
        .clone()
        .filter(|u| u.source == SOURCE_OFFICIAL)
        .unwrap_or_else(|| ProviderUsage::new(ID, SOURCE_OFFICIAL));

    // Ahead of the back-off: renewing never touches the usage endpoint.
    if let Some(credential) = read_credential() {
        if maybe_renew(&credential, &mut saved, now, kiro_bin) {
            saved.consecutive_429 = 0;
            saved.backoff_until = None;
        }
    }

    if let Some(until) = saved.backing_off(now) {
        usage.status = if usage.windows.is_empty() { Status::Backoff } else { Status::Stale };
        usage.backoff_until = Some(until);
        usage.note = Some(format!("Rate limited, retrying in {}s", until - now));
    } else if saved.due(now, POLL_SECS, ctx.force) {
        saved.last_attempt = Some(now);
        read_live(now, &mut saved, &mut usage);
    }

    saved.usage = Some(usage.clone());
    saved.save(ID);

    // Never read yet: today's credits off disk beat an empty cell.
    if usage.windows.is_empty() && usage.status != Status::Ok {
        let mut fallback = local();
        fallback.note = usage.note.take();
        fallback.backoff_until = usage.backoff_until;
        return fallback;
    }
    usage
}

fn read_live(now: i64, saved: &mut Saved, usage: &mut ProviderUsage) {
    let Some(credential) = read_credential() else {
        usage.status = Status::NeedsAuth;
        usage.note = Some("No kiro-cli sign-in found — run kiro-cli login".into());
        return;
    };
    if credential.expired(now) {
        usage.status = if usage.windows.is_empty() { Status::NeedsAuth } else { Status::Stale };
        usage.note = Some(EXPIRED_NOTE.into());
        return;
    }

    match request(&credential) {
        Ok(reply) => {
            saved.consecutive_429 = 0;
            saved.backoff_until = None;
            usage.backoff_until = None;
            usage.fetched_at = Some(now);
            usage.source = SOURCE_OFFICIAL.into();
            usage.metered = true;
            usage.plan = plan(&reply);
            match credit_window(&reply) {
                Some(window) => {
                    usage.status = Status::Ok;
                    usage.headline = Some(window.id.clone());
                    usage.windows = vec![window];
                    usage.note = None;
                }
                None => {
                    usage.status = Status::None;
                    usage.windows.clear();
                    usage.note = Some("Kiro reported no credit limit".into());
                }
            }
        }
        Err(HttpError::Status { code: 401 | 403, .. }) => {
            usage.status = if usage.windows.is_empty() { Status::NeedsAuth } else { Status::Stale };
            usage.note = Some(if credential.expired(now + RENEW_MARGIN_SECS) {
                EXPIRED_NOTE.into()
            } else {
                "Kiro rejected its sign-in — run kiro-cli login again".into()
            });
        }
        Err(HttpError::Status { code: 429, retry_after }) => {
            saved.consecutive_429 += 1;
            let wait = store::backoff_secs(saved.consecutive_429 - 1, retry_after.unwrap_or(0));
            let until = now.saturating_add(i64::try_from(wait).unwrap_or(i64::MAX / 2));
            saved.backoff_until = Some(until);
            usage.backoff_until = Some(until);
            usage.status = if usage.windows.is_empty() { Status::Backoff } else { Status::Stale };
            usage.note = Some(format!("Rate limited, retrying in {wait}s"));
        }
        Err(err) => {
            usage.status = if usage.windows.is_empty() { Status::Error } else { Status::Stale };
            usage.note = Some(err.to_string());
        }
    }
}

fn request(credential: &Credential) -> Result<Value, HttpError> {
    let url = format!(
        "https://q.{}.amazonaws.com/getUsageLimits?origin=KIRO_CLI&profileArn={}&resourceType=AGENTIC_REQUEST&isEmailRequired=false",
        region(&credential.profile_arn),
        encode(&credential.profile_arn)
    );
    let bearer = format!("Bearer {}", credential.token);
    http::get_json(&url, &[("Authorization", bearer.as_str()), ("Accept", "application/json")])
}

/// `arn:aws:codewhisperer:us-east-1:…` → `us-east-1`. Anything that does not
/// look like a region name falls back to us-east-1 rather than reaching an
/// arbitrary host.
fn region(arn: &str) -> &str {
    arn.split(':')
        .nth(3)
        .filter(|r| !r.is_empty() && r.len() <= 32 && r.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-'))
        .unwrap_or("us-east-1")
}

fn encode(text: &str) -> String {
    text.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

/// The month's credits as a window; `used` is a share of the whole allowance,
/// the free trial's included while it is active.
fn credit_window(reply: &Value) -> Option<UsageWindow> {
    let list = reply.get("usageBreakdownList")?.as_array()?;
    let entry = list
        .iter()
        .find(|e| e.get("resourceType").and_then(Value::as_str) == Some("CREDIT"))
        .or_else(|| list.first())?;
    let number = |v: &Value, precise: &str, plain: &str| {
        v.get(precise).and_then(Value::as_f64).or_else(|| v.get(plain).and_then(Value::as_f64))
    };
    let mut used = number(entry, "currentUsageWithPrecision", "currentUsage")?;
    let mut limit = number(entry, "usageLimitWithPrecision", "usageLimit")?;
    if let Some(trial) = entry.get("freeTrialInfo") {
        if trial.get("freeTrialStatus").and_then(Value::as_str) == Some("ACTIVE") {
            used += number(trial, "currentUsageWithPrecision", "currentUsage").unwrap_or(0.0);
            limit += number(trial, "usageLimitWithPrecision", "usageLimit").unwrap_or(0.0);
        }
    }
    if !limit.is_finite() || limit <= 0.0 || !used.is_finite() {
        return None;
    }
    let resets_at = entry
        .get("nextDateReset")
        .or_else(|| reply.get("nextDateReset"))
        .and_then(Value::as_f64)
        .map(|secs| secs as i64);
    let mut window = UsageWindow::new(WINDOW_ID, "Monthly credits", used / limit * 100.0, None, resets_at);
    window.amount = Some(Amount { used, limit, unit: "credits".into() });
    Some(window)
}

/// `KIRO FREE` → `Kiro Free`.
fn plan(reply: &Value) -> Option<String> {
    let title = reply.pointer("/subscriptionInfo/subscriptionTitle")?.as_str()?.trim();
    let words: Vec<String> = title
        .split_whitespace()
        .map(|word| {
            let lower = word.to_lowercase();
            let mut chars = lower.chars();
            chars.next().map(|c| c.to_uppercase().collect::<String>() + chars.as_str()).unwrap_or_default()
        })
        .collect();
    (!words.is_empty()).then(|| words.join(" "))
}

// ---------------- the credential ----------------

struct Credential {
    token: String,
    expires_at: Option<i64>,
    profile_arn: String,
}

impl Credential {
    fn expired(&self, now: i64) -> bool {
        self.expires_at.is_some_and(|at| at <= now)
    }
}

fn read_credential() -> Option<Credential> {
    let db = data_db().ok()?;
    let uri = format!("file:{}?mode=ro", db.display());
    let conn = Connection::open_with_flags(&uri, OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_URI).ok()?;
    credential_from(&conn)
}

/// The social sign-in is the one checked against a real database; any other
/// `kirocli:*:token` row is read the same way, if it has the same fields.
fn credential_from(conn: &Connection) -> Option<Credential> {
    let mut statement = conn
        .prepare("SELECT value FROM auth_kv WHERE key LIKE 'kirocli:%:token' ORDER BY key = 'kirocli:social:token' DESC")
        .ok()?;
    let rows: Vec<String> = statement.query_map([], |row| row.get(0)).ok()?.flatten().collect();
    let profile_fallback = conn
        .query_row("SELECT value FROM state WHERE key = 'api.codewhisperer.profile'", [], |row| row.get::<_, String>(0))
        .optional()
        .ok()
        .flatten()
        .and_then(|text| serde_json::from_str::<Value>(&text).ok())
        .and_then(|value| value.get("arn")?.as_str().map(str::to_string));
    rows.iter().find_map(|text| {
        let value: Value = serde_json::from_str(text).ok()?;
        let token = value.get("access_token")?.as_str()?.trim();
        if token.is_empty() {
            return None;
        }
        let profile_arn = value
            .get("profile_arn")
            .and_then(Value::as_str)
            .map(str::to_string)
            .or_else(|| profile_fallback.clone())?;
        Some(Credential {
            token: token.to_string(),
            expires_at: value.get("expires_at").and_then(Value::as_str).and_then(time::rfc3339_to_unix),
            profile_arn,
        })
    })
}

// ---------------- sign-in renewal ----------------

/// Pure, so every branch is testable without a clock or a subprocess.
fn should_renew(expires_at: Option<i64>, now: i64, attempted_for: Option<i64>, last_attempt: Option<i64>) -> bool {
    let Some(expiry) = expires_at else { return false };
    if expiry > now + RENEW_MARGIN_SECS {
        return false;
    }
    if attempted_for == Some(expiry) {
        return false;
    }
    last_attempt.is_none_or(|at| now - at >= RENEW_COOLDOWN_SECS)
}

fn maybe_renew(credential: &Credential, saved: &mut Saved, now: i64, kiro_bin: &Binary) -> bool {
    if !should_renew(credential.expires_at, now, saved.renew_attempted_for, saved.renew_last_attempt) {
        return false;
    }
    saved.renew_last_attempt = Some(now);
    saved.renew_attempted_for = credential.expires_at;
    let Some(cli) = find_cli(kiro_bin) else { return false };
    if run_renewal(&cli).is_err() {
        return false;
    }
    let after = read_credential().and_then(|c| c.expires_at);
    matches!((after, credential.expires_at), (Some(a), Some(b)) if a > b)
}

/// An explicit `kiro.binary_path` is trusted outright; otherwise PATH, then
/// the directory kiro-cli's installer uses.
fn find_cli(kiro_bin: &Binary) -> Option<PathBuf> {
    if let Some(path) = kiro_bin.binary_path.as_deref().map(str::trim).filter(|p| !p.is_empty()) {
        return Some(PathBuf::from(path));
    }
    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Some(path) = std::env::var_os("PATH") {
        candidates.extend(std::env::split_paths(&path).map(|dir| dir.join("kiro-cli")));
    }
    if let Ok(home) = paths::home_dir() {
        candidates.push(home.join(".local/bin/kiro-cli"));
    }
    candidates.into_iter().find(|path| {
        use std::os::unix::fs::PermissionsExt;
        std::fs::metadata(path).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
    })
}

/// `kiro-cli whoami` renews an expiring sign-in as a side effect. Its output
/// (the account's email) is discarded.
fn run_renewal(cli: &Path) -> std::io::Result<()> {
    let mut child = Command::new(cli)
        .arg("whoami")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    let deadline = Instant::now() + RENEW_TIMEOUT;
    while child.try_wait()?.is_none() {
        if Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            break;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    Ok(())
}

// ---------------- session files ----------------

#[derive(Deserialize)]
struct Record {
    created_at: Option<String>,
    updated_at: Option<String>,
    title: Option<String>,
    cwd: Option<String>,
    session_state: Option<State>,
}

#[derive(Deserialize)]
struct State {
    conversation_metadata: Option<Metadata>,
    rts_model_state: Option<ModelState>,
}

#[derive(Deserialize)]
struct ModelState {
    model_info: Option<ModelInfo>,
}

#[derive(Deserialize)]
struct ModelInfo {
    model_id: Option<String>,
}

#[derive(Deserialize)]
struct Metadata {
    #[serde(default)]
    user_turn_metadatas: Vec<Turn>,
}

#[derive(Deserialize)]
struct Turn {
    end_timestamp: Option<String>,
    #[serde(default)]
    metering_usage: Vec<Metering>,
}

#[derive(Deserialize)]
struct Metering {
    value: f64,
    unit: String,
}

struct Session {
    title: String,
    project: String,
    started_at: i64,
    last_seen: i64,
    /// Each model request as (unix seconds, credits), timed at its turn's end.
    requests: Vec<(i64, f64)>,
    /// The session's model: kiro-cli records one per session, not per request.
    model: Option<String>,
}

#[derive(Default)]
struct Scan {
    sessions: Vec<Session>,
    error: Option<String>,
}

/// Every session file written to since `cutoff_secs`; older files are not
/// opened. The first file that fails to parse is kept, the rest still read.
fn scan(dir: &Path, cutoff_secs: i64) -> Scan {
    let mut scan = Scan::default();
    let Ok(entries) = std::fs::read_dir(dir) else {
        return scan;
    };
    for path in entries.flatten().map(|entry| entry.path()) {
        if path.extension().is_none_or(|ext| ext != "json") || !path.is_file() {
            continue;
        }
        if paths::mtime_secs(&path).is_some_and(|at| at < cutoff_secs) {
            continue;
        }
        match read_session(&path) {
            Ok(Some(session)) => scan.sessions.push(session),
            Ok(None) => {}
            Err(err) => {
                scan.error.get_or_insert_with(|| format!("{}: {err:#}", path.display()));
            }
        }
    }
    scan
}

fn read_session(path: &Path) -> Result<Option<Session>> {
    let record: Record = serde_json::from_str(&std::fs::read_to_string(path)?)?;
    let Some(started_at) = record.created_at.as_deref().and_then(time::rfc3339_to_unix) else {
        return Ok(None);
    };
    let (turns, model) = match record.session_state {
        Some(state) => (
            state.conversation_metadata.map(|m| m.user_turn_metadatas).unwrap_or_default(),
            state.rts_model_state.and_then(|m| m.model_info).and_then(|i| i.model_id),
        ),
        None => (Vec::new(), None),
    };

    let mut requests = Vec::new();
    for turn in turns {
        let Some(at) = turn.end_timestamp.as_deref().and_then(time::rfc3339_to_unix) else {
            continue;
        };
        requests.extend(
            turn.metering_usage
                .into_iter()
                .filter(|m| m.unit.eq_ignore_ascii_case("credit") && m.value.is_finite())
                .map(|m| (at, m.value)),
        );
    }

    let last_seen = record
        .updated_at
        .as_deref()
        .and_then(time::rfc3339_to_unix)
        .unwrap_or(started_at)
        .max(started_at);
    Ok(Some(Session {
        title: record.title.unwrap_or_default(),
        project: record.cwd.as_deref().map(sessions::folder_name).unwrap_or_default(),
        started_at,
        last_seen,
        requests,
        model,
    }))
}

/// For `flare doctor`. The sign-in is described by its expiry, never its value.
pub fn probe() -> Vec<String> {
    let mut lines = probe_sessions();
    lines.push(match read_credential() {
        Some(credential) => match credential.expires_at {
            Some(at) => format!(
                "sign-in: found (region {}), expires in {}s",
                region(&credential.profile_arn),
                at - paths::now_secs()
            ),
            None => "sign-in: found, no expiry recorded".into(),
        },
        None => "sign-in: not found — run kiro-cli login for the monthly credit limit".into(),
    });
    lines
}

fn probe_sessions() -> Vec<String> {
    match sessions_dir() {
        Ok(dir) => {
            let newest = std::fs::read_dir(&dir)
                .map(|entries| entries.flatten().filter_map(|e| paths::mtime_secs(&e.path())).max())
                .ok();
            match newest {
                Some(Some(at)) => vec![format!(
                    "sessions: found ({}), last written {}s ago",
                    dir.display(),
                    paths::now_secs() - at
                )],
                Some(None) => vec![format!("sessions: none yet ({})", dir.display())],
                None => vec![format!("sessions: NOT FOUND ({}) — not installed", dir.display())],
            }
        }
        Err(err) => vec![format!("home: unresolved ({err:#})")],
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::{NO_CUTOFF, fixture};

    #[test]
    fn times_each_request_at_its_turns_end() {
        let session = read_session(&fixture("kiro/sessions_ok/a.json")).expect("read").expect("session");
        assert_eq!(session.project, "flare");
        assert_eq!(session.title, "tidy the parser");
        assert_eq!(session.started_at, time::rfc3339_to_unix("2026-09-12T20:36:34Z").unwrap());
        let end = time::rfc3339_to_unix("2026-09-12T20:37:43Z").unwrap();
        assert_eq!(session.requests, vec![(end, 0.5), (end, 0.25)]);
        assert_eq!(session.model.as_deref(), Some("claude-sonnet-4.5"));
    }

    #[test]
    fn a_session_with_no_turns_yet_has_no_requests() {
        let session = read_session(&fixture("kiro/sessions_ok/empty.json")).expect("read").expect("session");
        assert!(session.requests.is_empty());
        assert_eq!(session.last_seen, session.started_at);
    }

    #[test]
    fn reads_the_months_credits_from_a_real_reply() {
        let reply: Value = serde_json::from_str(&std::fs::read_to_string(fixture("kiro/usage_limits.json")).unwrap()).unwrap();
        let window = credit_window(&reply).expect("window");
        assert_eq!(window.id, WINDOW_ID);
        assert!((window.used - 0.17 / 50.0).abs() < 1e-9);
        assert_eq!(window.resets_at, Some(1_790_812_800));
        assert_eq!(window.amount, Some(Amount { used: 0.17, limit: 50.0, unit: "credits".into() }));
        assert_eq!(plan(&reply).as_deref(), Some("Kiro Free"));
    }

    #[test]
    fn an_active_free_trial_adds_to_the_allowance() {
        let mut reply: Value = serde_json::from_str(&std::fs::read_to_string(fixture("kiro/usage_limits.json")).unwrap()).unwrap();
        reply["usageBreakdownList"][0]["freeTrialInfo"]["freeTrialStatus"] = "ACTIVE".into();
        let amount = credit_window(&reply).and_then(|w| w.amount).expect("amount");
        assert!((amount.used - 495.69).abs() < 1e-9);
        assert!((amount.limit - 550.0).abs() < 1e-9);
    }

    #[test]
    fn a_reply_without_a_limit_is_no_window() {
        assert!(credit_window(&serde_json::json!({ "usageBreakdownList": [] })).is_none());
        assert!(credit_window(&serde_json::json!({ "usageBreakdownList": [{ "resourceType": "CREDIT", "currentUsage": 1, "usageLimit": 0 }] })).is_none());
    }

    #[test]
    fn the_region_comes_from_the_profile_and_nowhere_odd() {
        assert_eq!(region("arn:aws:codewhisperer:eu-central-1:1:profile/X"), "eu-central-1");
        assert_eq!(region("arn:aws:codewhisperer:evil.example/x:1:profile/X"), "us-east-1");
        assert_eq!(region("nonsense"), "us-east-1");
        assert_eq!(encode("arn:aws:x/Y"), "arn%3Aaws%3Ax%2FY");
    }

    #[test]
    fn reads_the_social_sign_in_row() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(
            r#"CREATE TABLE auth_kv (key text PRIMARY KEY, value text);
               CREATE TABLE state (key text PRIMARY KEY, value text);
               INSERT INTO auth_kv VALUES ('kirocli:social:token',
                 '{"access_token":"t0k","expires_at":"2026-09-22T23:37:40.648587164Z","refresh_token":"r","provider":"google","profile_arn":"arn:aws:codewhisperer:us-east-1:1:profile/P"}');"#,
        )
        .unwrap();
        let credential = credential_from(&conn).expect("credential");
        assert_eq!(credential.token, "t0k");
        assert_eq!(credential.profile_arn, "arn:aws:codewhisperer:us-east-1:1:profile/P");
        assert_eq!(credential.expires_at, time::rfc3339_to_unix("2026-09-22T23:37:40Z"));
    }

    #[test]
    fn renews_once_per_token_near_its_expiry() {
        assert!(!should_renew(None, 1000, None, None));
        assert!(!should_renew(Some(1000 + RENEW_MARGIN_SECS + 1), 1000, None, None));
        assert!(should_renew(Some(1100), 1000, None, None));
        assert!(!should_renew(Some(1100), 1000, Some(1100), None));
        assert!(!should_renew(Some(1100), 1000, None, Some(900)));
        assert!(should_renew(Some(1100), 1000, None, Some(1000 - RENEW_COOLDOWN_SECS)));
    }

    #[test]
    fn a_broken_file_is_reported_and_the_rest_still_read() {
        let scan = scan(&fixture("kiro/sessions_malformed"), NO_CUTOFF);
        assert_eq!(scan.sessions.len(), 1);
        assert!(scan.error.is_some_and(|e| e.contains("broken.json")));
    }
}
