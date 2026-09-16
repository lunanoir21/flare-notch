//! Claude Code provider.
//!
//! Official mode, as Codenotch reads it:
//!
//! ```text
//! GET https://api.anthropic.com/api/oauth/usage
//! Authorization: Bearer <the token Claude Code keeps in ~/.claude/.credentials.json>
//! anthropic-beta: oauth-2025-04-20
//! ```
//!
//! - An expired token is never sent: the endpoint answers one with a long 429,
//!   not a 401, which would read as "rate limited" for as long as it stays stale.
//! - Shortly before expiry the token is renewed by running `claude -p`, which
//!   starts up, renews, and exits for want of a prompt. Nothing here writes
//!   the credential file.
//! - A 401/403 re-reads the credential once, in case Claude Code just rotated it.
//! - A 429 backs off from a minute, doubling to 15, and the deadline survives
//!   restarts.
//! - A failed read keeps the last reading, marked stale. Nothing is invented.
//!
//! Where the endpoint cannot answer, a status line capture younger than half an
//! hour stands in. Local mode reads only that capture, which
//! hooks/claude-statusline-capture.sh writes.
//!
//! Tokens for the day come from ~/.claude/projects/**/*.jsonl in both modes.

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use anyhow::Result;
use serde_json::Value;

use crate::config::{Binary, DataMode};
use crate::http::{self, HttpError};
use crate::store::{self, Saved};
use crate::{
    Config, Fetch, ProviderUsage, SOURCE_LOCAL, SOURCE_OFFICIAL, Status, UsageProvider,
    UsageWindow, err_parse, jsonl, paths,
};

const ID: &str = "claude";
const ENDPOINT: &str = "https://api.anthropic.com/api/oauth/usage";
const POLL_SECS: i64 = 60;
/// Under Claude Code's own five minutes: it renews only when that close, so
/// launching earlier does nothing.
const RENEW_MARGIN_MS: i64 = 4 * 60 * 1000;
const RENEW_COOLDOWN_SECS: i64 = 10 * 60;
const RENEW_TIMEOUT: Duration = Duration::from_secs(30);
const CAPTURE_FRESH_FOR_SECS: i64 = 30 * 60;
const EXPIRED_NOTE: &str = "Credential expired — run claude once in a terminal to renew it";

pub struct Claude {
    config: Config,
}

impl Claude {
    pub fn new(config: Config) -> Self {
        Self { config }
    }
}

impl UsageProvider for Claude {
    fn id(&self) -> &'static str {
        ID
    }

    fn fetch(&self, ctx: &Fetch) -> Result<ProviderUsage> {
        let home = paths::claude_home()?;
        if !home.exists() {
            return Ok(ProviderUsage::absent(ID));
        }

        let mut usage = match self.config.data.mode {
            DataMode::Official => official(ctx, &home, &self.config.claude),
            DataMode::Local => local(),
        };

        usage.account = read_account();
        let scan = scan_tokens(&home.join("projects"), self.config.scan_cutoff_secs());
        usage.tokens_today = Some(scan.tokens);
        if let Some(err) = scan.parse_error {
            usage.error = Some(err_parse(err));
        }
        usage.settle(ctx.now);
        Ok(usage)
    }
}

fn local() -> ProviderUsage {
    let mut usage = ProviderUsage::new(ID, SOURCE_LOCAL);
    match read_capture() {
        Some(captured) => {
            usage.status = Status::Ok;
            usage.windows = captured.windows;
            usage.fetched_at = captured.captured_at;
            usage.headline = Some("session".into());
        }
        None => {
            usage.note = Some(
                "No status line capture yet — point Claude Code's statusLine at hooks/claude-statusline-capture.sh"
                    .into(),
            )
        }
    }
    usage
}

fn official(ctx: &Fetch, home: &Path, claude_bin: &Binary) -> ProviderUsage {
    let now = ctx.now;
    let credentials = credentials_path(home);
    let mut saved = Saved::load(ID);
    let mut usage = saved
        .usage
        .clone()
        .filter(|u| u.source == SOURCE_OFFICIAL)
        .unwrap_or_else(|| ProviderUsage::new(ID, SOURCE_OFFICIAL));

    // Ahead of the back-off: renewing never touches the usage endpoint, and a
    // fresh token deserves a fresh try.
    if let Some(credential) = read_credentials(&credentials) {
        if maybe_renew(&credential, &credentials, &mut saved, now, claude_bin) {
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
        read_live(&credentials, now, &mut saved, &mut usage);
    }

    saved.usage = Some(usage.clone());
    saved.save(ID);

    if usage.status != Status::Ok && usage.windows.is_empty() {
        if let Some(captured) = read_capture() {
            if captured
                .captured_at
                .is_some_and(|at| now - at <= CAPTURE_FRESH_FOR_SECS)
            {
                let why = usage.note.take();
                usage.status = Status::Ok;
                usage.source = SOURCE_LOCAL.into();
                usage.windows = captured.windows;
                usage.fetched_at = captured.captured_at;
                usage.headline = Some("session".into());
                usage.note = Some(match why {
                    Some(why) => format!("{why} · from the status line"),
                    None => "from the status line".into(),
                });
            }
        }
    }
    usage
}

fn read_live(path: &Path, now: i64, saved: &mut Saved, usage: &mut ProviderUsage) {
    let Some(credential) = read_credentials(path) else {
        usage.status = Status::NeedsAuth;
        usage.note = Some("No Claude Code credential found — sign in with claude once".into());
        return;
    };
    if credential.expired(now) {
        usage.status = if usage.windows.is_empty() { Status::NeedsAuth } else { Status::Stale };
        usage.note = Some(EXPIRED_NOTE.into());
        return;
    }

    let result = match request(&credential.token) {
        Err(HttpError::Status { code: 401 | 403, .. }) => match read_credentials(path) {
            Some(again) if again.token != credential.token && !again.expired(now) => {
                request(&again.token)
            }
            _ => Err(HttpError::Status { code: 401, retry_after: None }),
        },
        other => other,
    };

    match result {
        Ok(reply) => {
            let windows = parse_response(&reply);
            saved.consecutive_429 = 0;
            saved.backoff_until = None;
            usage.backoff_until = None;
            usage.fetched_at = Some(now);
            usage.plan = credential.plan;
            usage.source = SOURCE_OFFICIAL.into();
            if windows.is_empty() {
                usage.status = Status::None;
                usage.windows.clear();
                usage.note = Some("Claude reported no usage windows".into());
            } else {
                usage.status = Status::Ok;
                usage.headline = Some(if windows.iter().any(|w| w.id == "session") {
                    "session".to_string()
                } else {
                    windows[0].id.clone()
                });
                usage.windows = windows;
                usage.note = None;
            }
        }
        Err(HttpError::Status { code: 401 | 403, .. }) => {
            usage.status = Status::NeedsAuth;
            usage.note = Some("Credential rejected (switched accounts?)".into());
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

fn request(token: &str) -> Result<Value, HttpError> {
    let bearer = format!("Bearer {token}");
    http::get_json(
        ENDPOINT,
        &[
            ("Authorization", bearer.as_str()),
            ("anthropic-beta", "oauth-2025-04-20"),
        ],
    )
}

// ---------------- the reply ----------------

/// `limits` is the forward-compatible shape and is read first. `five_hour` and
/// `seven_day` are merged in because a window that has just rolled over drops
/// out of `limits` while the named field still carries it; they are matched
/// against what is already there by id alias, by label, and by identical reset
/// and percentage, or the card shows the same window twice.
fn parse_response(reply: &Value) -> Vec<UsageWindow> {
    let mut out: Vec<UsageWindow> = Vec::new();

    if let Some(limits) = reply.get("limits").and_then(Value::as_array) {
        for limit in limits {
            let Some(kind) = limit.get("kind").and_then(Value::as_str) else { continue };
            let Some(percent) = limit.get("percent").and_then(Value::as_f64) else { continue };
            // A window without a reset time is not shown.
            let Some(resets_at) = limit.get("resets_at").and_then(rfc3339) else { continue };
            let label = limit
                .pointer("/scope/model/display_name")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|name| !name.is_empty())
                .map(|name| format!("Weekly ({name})"))
                .unwrap_or_else(|| label_for(kind));
            out.push(UsageWindow::new(kind, label, percent, minutes_for(kind), Some(resets_at)));
        }
    }

    let named: [(&str, &str, &[&str]); 2] = [
        ("five_hour", "session", &["session", "five_hour"]),
        ("seven_day", "weekly_all", &["seven_day", "weekly_all", "weekly"]),
    ];
    for (field, id, aliases) in named {
        let Some(window) = reply.get(field) else { continue };
        let Some(utilization) = window.get("utilization").and_then(Value::as_f64) else { continue };
        let resets_at = window.get("resets_at").and_then(rfc3339);
        let label = label_for(id);
        let used = (utilization / 100.0).clamp(0.0, 1.0);
        let duplicate = out.iter().any(|w| {
            aliases.contains(&w.id.as_str())
                || w.label == label
                || (resets_at.is_some() && w.resets_at == resets_at && (w.used - used).abs() < 0.005)
        });
        if !duplicate {
            out.push(UsageWindow::new(id, label, utilization, minutes_for(id), resets_at));
        }
    }

    out.sort_by_key(|w| match w.id.as_str() {
        "session" => 0,
        "weekly_all" | "seven_day" => 1,
        _ => 2,
    });
    out
}

fn rfc3339(value: &Value) -> Option<i64> {
    value.as_str().and_then(crate::time::rfc3339_to_unix)
}

fn label_for(kind: &str) -> String {
    match kind {
        "session" | "five_hour" => "Current session".into(),
        "seven_day" | "weekly_all" => "Weekly (all models)".into(),
        "seven_day_opus" | "weekly_opus" => "Weekly (Opus)".into(),
        "weekly_sonnet" => "Weekly (Sonnet)".into(),
        "weekly_scoped" => "Weekly (model-scoped)".into(),
        other => {
            let spaced = other.replace("weekly_", "").replace('_', " ");
            let mut chars = spaced.chars();
            match chars.next() {
                Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
                None => String::new(),
            }
        }
    }
}

fn minutes_for(kind: &str) -> Option<i64> {
    if kind == "session" || kind == "five_hour" {
        Some(300)
    } else if kind.starts_with("weekly") || kind.starts_with("seven_day") {
        Some(10_080)
    } else {
        None
    }
}

// ---------------- the credential ----------------

struct Credential {
    token: String,
    expires_at_ms: Option<i64>,
    plan: Option<String>,
}

impl Credential {
    fn expired(&self, now: i64) -> bool {
        self.expires_at_ms
            .is_some_and(|ms| ms <= now.saturating_mul(1000))
    }
}

fn credentials_path(home: &Path) -> PathBuf {
    home.join(".credentials.json")
}

fn read_credentials(path: &Path) -> Option<Credential> {
    [path.to_path_buf(), path.with_file_name("credentials.json")]
        .iter()
        .find_map(|candidate| {
            let text = std::fs::read_to_string(candidate).ok()?;
            let value: Value = serde_json::from_str(&text).ok()?;
            let oauth = value.get("claudeAiOauth").unwrap_or(&value);
            let token = oauth.get("accessToken")?.as_str()?.trim();
            if token.is_empty() {
                return None;
            }
            Some(Credential {
                token: token.to_string(),
                expires_at_ms: oauth
                    .get("expiresAt")
                    .and_then(Value::as_f64)
                    .map(|ms| ms as i64),
                plan: oauth
                    .get("subscriptionType")
                    .and_then(Value::as_str)
                    .map(str::to_string),
            })
        })
}

// ---------------- token renewal ----------------

/// Pure, so every branch is testable without a clock or a subprocess.
fn should_renew(
    expires_at_ms: Option<i64>,
    now: i64,
    attempted_for: Option<i64>,
    last_attempt: Option<i64>,
) -> bool {
    // Nothing read yet: never launch on a guess.
    let Some(expiry) = expires_at_ms else { return false };
    if expiry > now.saturating_mul(1000) + RENEW_MARGIN_MS {
        return false;
    }
    // One attempt per token: one that failed to move the expiry never runs again.
    if attempted_for == Some(expiry) {
        return false;
    }
    last_attempt.is_none_or(|at| now - at >= RENEW_COOLDOWN_SECS)
}

/// Judged on the outcome, never the exit status: refusing the empty prompt is
/// a non-zero exit and a successful renewal at the same time.
fn maybe_renew(
    credential: &Credential,
    path: &Path,
    saved: &mut Saved,
    now: i64,
    claude_bin: &Binary,
) -> bool {
    if !should_renew(
        credential.expires_at_ms,
        now,
        saved.renew_attempted_for,
        saved.renew_last_attempt,
    ) {
        return false;
    }
    saved.renew_last_attempt = Some(now);
    saved.renew_attempted_for = credential.expires_at_ms;
    let Some(cli) = find_cli(claude_bin) else { return false };
    if run_renewal(&cli).is_err() {
        return false;
    }
    let after = read_credentials(path).and_then(|c| c.expires_at_ms);
    matches!((after, credential.expires_at_ms), (Some(a), Some(b)) if a > b)
}

/// Where Claude Code installs itself. An explicit `claude.binary_path`
/// override is trusted outright and nothing else is tried; otherwise PATH,
/// then a fixed list of well-known install directories, first match wins —
/// all of them locations another program could also have written to, which
/// is exactly what the override exists to let a user route around.
pub fn find_cli(claude_bin: &Binary) -> Option<PathBuf> {
    if let Some(path) = override_path(claude_bin) {
        return Some(path);
    }
    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Some(path) = std::env::var_os("PATH") {
        candidates.extend(std::env::split_paths(&path).map(|dir| dir.join("claude")));
    }
    if let Some(home) = dirs::home_dir() {
        for rel in [
            ".local/bin/claude",
            ".claude/local/claude",
            ".bun/bin/claude",
            ".volta/bin/claude",
            ".npm-global/bin/claude",
        ] {
            candidates.push(home.join(rel));
        }
        if let Ok(entries) = std::fs::read_dir(home.join(".nvm/versions/node")) {
            let mut trees: Vec<PathBuf> = entries.flatten().map(|e| e.path()).collect();
            trees.sort();
            candidates.extend(trees.into_iter().rev().map(|tree| tree.join("bin/claude")));
        }
    }
    candidates.into_iter().find(|path| is_executable(path))
}

/// Pure, so it is testable without touching PATH or the filesystem.
fn override_path(claude_bin: &Binary) -> Option<PathBuf> {
    let trimmed = claude_bin.binary_path.as_deref()?.trim();
    (!trimmed.is_empty()).then(|| PathBuf::from(trimmed))
}

fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(path).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}

/// `claude -p` with a null stdin: no conversation, no transcript, output
/// discarded because a token could in principle be echoed into it.
fn run_renewal(cli: &Path) -> std::io::Result<()> {
    let mut command = Command::new(cli);
    command
        .arg("-p")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    // Started from inside a Claude Code session, the child would take the
    // host's auth and leave the file alone.
    for (key, _) in std::env::vars_os() {
        let key = key.to_string_lossy().into_owned();
        if key == "CLAUDECODE" || key.starts_with("CLAUDE_CODE_") {
            command.env_remove(&key);
        }
    }
    let mut child = command.spawn()?;
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

// ---------------- local sources ----------------

#[derive(Default)]
struct Scan {
    tokens: u64,
    parse_error: Option<String>,
}

/// Sum the token counts recorded at or after `cutoff_secs`. Files untouched
/// since the cutoff are skipped without being opened.
fn scan_tokens(projects: &Path, cutoff_secs: i64) -> Scan {
    let mut scan = Scan::default();

    for path in paths::collect_files(projects, "jsonl") {
        if paths::mtime_secs(&path).is_some_and(|mtime| mtime < cutoff_secs) {
            continue;
        }

        let mut file_tokens: u64 = 0;
        let result = jsonl::for_each(&path, |value| {
            if value.get("type").and_then(Value::as_str) != Some("assistant") {
                return;
            }
            let Some(timestamp) = value.get("timestamp").and_then(Value::as_str) else {
                return;
            };
            if crate::time::rfc3339_to_unix(timestamp).is_none_or(|at| at < cutoff_secs) {
                return;
            }
            let Some(usage) = value.pointer("/message/usage") else {
                return;
            };
            file_tokens = file_tokens.saturating_add(token_total(usage));
        });

        match result {
            Ok(()) => scan.tokens = scan.tokens.saturating_add(file_tokens),
            Err(err) => {
                if scan.parse_error.is_none() {
                    scan.parse_error = Some(format!("{err:#}"));
                }
            }
        }
    }

    scan
}

/// Only the top-level counters: the sibling `iterations` array repeats the
/// same turn, so reading it too would double count.
fn token_total(usage: &Value) -> u64 {
    const FIELDS: [&str; 4] = [
        "input_tokens",
        "output_tokens",
        "cache_creation_input_tokens",
        "cache_read_input_tokens",
    ];
    FIELDS
        .iter()
        .filter_map(|field| usage.get(*field).and_then(Value::as_u64))
        .sum()
}

struct Captured {
    windows: Vec<UsageWindow>,
    captured_at: Option<i64>,
}

fn read_capture() -> Option<Captured> {
    read_capture_from(&paths::flare_state().ok()?.join("claude-statusline.json"))
}

/// The status line payload names its windows instead of giving a duration.
fn read_capture_from(path: &Path) -> Option<Captured> {
    let text = std::fs::read_to_string(path).ok()?;
    let value: Value = serde_json::from_str(&text).ok()?;
    let limits = value.get("rate_limits")?;

    let windows: Vec<UsageWindow> = [("five_hour", "session"), ("seven_day", "weekly_all")]
        .into_iter()
        .filter_map(|(key, id)| {
            let block = limits.get(key)?;
            let used = block.get("used_percentage").and_then(Value::as_f64)?;
            let resets_at = block.get("resets_at").and_then(Value::as_i64);
            Some(UsageWindow::new(id, label_for(id), used, minutes_for(id), resets_at))
        })
        .collect();

    if windows.is_empty() {
        return None;
    }
    Some(Captured {
        windows,
        captured_at: paths::mtime_secs(path),
    })
}

/// The account lives in ~/.claude.json; nothing but the email is read.
fn read_account() -> Option<String> {
    read_account_from(&paths::claude_account_file().ok()?)
}

fn read_account_from(path: &Path) -> Option<String> {
    let text = std::fs::read_to_string(path).ok()?;
    let value: Value = serde_json::from_str(&text).ok()?;
    value
        .pointer("/oauthAccount/emailAddress")
        .and_then(Value::as_str)
        .map(str::to_string)
}

/// For `flare doctor`. Never prints a secret: a token is described by length.
pub fn probe(claude_bin: &Binary) -> Vec<String> {
    let mut lines = Vec::new();
    let now = paths::now_secs();
    match paths::claude_home() {
        Ok(home) => {
            let path = credentials_path(&home);
            match read_credentials(&path) {
                Some(credential) => {
                    let validity = match credential.expires_at_ms {
                        Some(ms) if ms / 1000 <= now => "expired".to_string(),
                        Some(ms) => format!("valid for {}m", (ms / 1000 - now) / 60),
                        None => "no expiry recorded".to_string(),
                    };
                    lines.push(format!(
                        "credential: found ({validity}, token {} chars, plan {})",
                        credential.token.len(),
                        credential.plan.as_deref().unwrap_or("unknown")
                    ));
                }
                None => lines.push(format!("credential: NOT FOUND ({})", path.display())),
            }
        }
        Err(err) => lines.push(format!("home: unresolved ({err:#})")),
    }
    lines.push(match find_cli(claude_bin) {
        Some(cli) => format!("token renewal: via {}", cli.display()),
        None => "token renewal: no claude CLI found".to_string(),
    });
    if let Ok(dir) = paths::flare_state() {
        let capture = dir.join("claude-statusline.json");
        lines.push(match paths::mtime_secs(&capture) {
            Some(at) => format!("status line capture: written {}s ago", now - at),
            None => format!("status line capture: none ({})", capture.display()),
        });
    }
    lines
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::{NO_CUTOFF, fixture};
    use serde_json::json;

    #[test]
    fn reads_limits_and_merges_the_named_windows_without_twins() {
        let reply = json!({
            "limits": [
                {"kind": "session", "percent": 73.0, "resets_at": "2026-09-15T18:00:00Z"},
                {"kind": "weekly_all", "percent": 7.0, "resets_at": "2026-09-18T00:00:00.123+00:00"},
                {"kind": "weekly_scoped", "percent": 40.0, "resets_at": "2026-09-18T00:00:00Z",
                 "scope": {"model": {"display_name": "Fable"}}},
                {"kind": "no_reset", "percent": 5.0}
            ],
            "five_hour": {"utilization": 73.0, "resets_at": "2026-09-15T18:00:00Z"},
            "seven_day": {"utilization": 7.0, "resets_at": "2026-09-18T00:00:00Z"}
        });
        let windows = parse_response(&reply);
        let ids: Vec<&str> = windows.iter().map(|w| w.id.as_str()).collect();
        assert_eq!(ids, ["session", "weekly_all", "weekly_scoped"]);
        let labels: Vec<&str> = windows.iter().map(|w| w.label.as_str()).collect();
        assert_eq!(labels, ["Current session", "Weekly (all models)", "Weekly (Fable)"]);
        assert!((windows[0].used - 0.73).abs() < 1e-9);
        assert_eq!(windows[0].window_minutes, Some(300));
    }

    #[test]
    fn a_window_that_just_rolled_out_of_limits_survives_through_its_named_field() {
        let reply = json!({
            "limits": [{"kind": "weekly_all", "percent": 20.0, "resets_at": "2026-09-18T00:00:00Z"}],
            "five_hour": {"utilization": 0.0, "resets_at": "2026-09-15T23:00:00Z"},
            "seven_day": {"utilization": 20.0, "resets_at": null}
        });
        let ids: Vec<String> = parse_response(&reply).into_iter().map(|w| w.id).collect();
        assert_eq!(ids, ["session", "weekly_all"]);
    }

    #[test]
    fn renews_only_near_expiry_once_per_token_and_after_a_cooldown() {
        let expiry_secs = 1_000_000;
        let expiry = Some(expiry_secs * 1000);
        assert!(!should_renew(None, expiry_secs, None, None));
        assert!(!should_renew(expiry, expiry_secs - 3600, None, None));
        assert!(should_renew(expiry, expiry_secs - 60, None, None));
        assert!(should_renew(expiry, expiry_secs + 3600, None, None));
        assert!(!should_renew(expiry, expiry_secs, expiry, None));
        assert!(!should_renew(Some(expiry_secs * 1000 + 5), expiry_secs, expiry, Some(expiry_secs - 60)));
        assert!(should_renew(
            Some(expiry_secs * 1000 + 5),
            expiry_secs,
            expiry,
            Some(expiry_secs - RENEW_COOLDOWN_SECS)
        ));
    }

    #[test]
    fn override_path_is_trusted_outright() {
        let bin = Binary { binary_path: Some("/opt/not-really-claude".into()) };
        assert_eq!(override_path(&bin), Some(PathBuf::from("/opt/not-really-claude")));
    }

    #[test]
    fn a_blank_or_unset_override_is_not_one() {
        assert_eq!(override_path(&Binary { binary_path: None }), None);
        assert_eq!(override_path(&Binary { binary_path: Some("   ".into()) }), None);
        assert_eq!(override_path(&Binary { binary_path: Some(String::new()) }), None);
    }

    #[test]
    fn reads_the_credential_and_judges_expiry_against_now() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join(".credentials.json");
        std::fs::write(
            &path,
            r#"{"claudeAiOauth":{"accessToken":"t0k","expiresAt":2000000,"subscriptionType":"pro"}}"#,
        )
        .unwrap();
        let credential = read_credentials(&path).expect("credential");
        assert_eq!(credential.token, "t0k");
        assert_eq!(credential.plan.as_deref(), Some("pro"));
        assert!(!credential.expired(1999));
        assert!(credential.expired(2000));

        std::fs::write(&path, r#"{"claudeAiOauth":{"accessToken":"  "}}"#).unwrap();
        assert!(read_credentials(&path).is_none());
    }

    #[test]
    fn sums_only_the_top_level_usage_counters() {
        let scan = scan_tokens(&fixture("claude/sessions_ok"), NO_CUTOFF);
        assert_eq!(scan.tokens, 1026);
        assert!(scan.parse_error.is_none());
    }

    #[test]
    fn a_truncated_final_line_does_not_lose_the_earlier_turns() {
        let scan = scan_tokens(&fixture("claude/sessions_truncated"), NO_CUTOFF);
        assert_eq!(scan.tokens, 1026);
        assert!(scan.parse_error.is_none());
    }

    #[test]
    fn damage_on_an_earlier_line_surfaces_as_a_parse_error() {
        let scan = scan_tokens(&fixture("claude/sessions_malformed"), NO_CUTOFF);
        assert!(scan.parse_error.is_some());
    }

    #[test]
    fn a_missing_projects_dir_yields_no_tokens_and_no_error() {
        let scan = scan_tokens(&fixture("claude/no_such_dir"), NO_CUTOFF);
        assert_eq!(scan.tokens, 0);
        assert!(scan.parse_error.is_none());
    }

    #[test]
    fn reads_both_windows_from_a_status_line_capture() {
        let captured =
            read_capture_from(&fixture("claude/statusline_ok.json")).expect("fixture has rate_limits");
        let session = &captured.windows[0];
        assert_eq!(session.id, "session");
        assert_eq!(session.label, "Current session");
        assert!((session.used - 0.63).abs() < 1e-9);
        assert_eq!(session.resets_at, Some(1787017800));
        let weekly = &captured.windows[1];
        assert_eq!(weekly.id, "weekly_all");
        assert!((weekly.used - 0.72).abs() < 1e-9);
    }

    #[test]
    fn a_capture_without_rate_limits_yields_no_windows() {
        assert!(read_capture_from(&fixture("claude/statusline_no_limits.json")).is_none());
        assert!(read_capture_from(&fixture("claude/no_such_capture.json")).is_none());
    }

    #[test]
    fn labels_the_account_from_the_account_file() {
        let account = read_account_from(&fixture("claude/account_ok.json"));
        assert_eq!(account.as_deref(), Some("redacted@example.invalid"));
        assert!(read_account_from(&fixture("claude/no_such_account.json")).is_none());
    }
}
