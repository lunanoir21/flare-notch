//! Codex provider.
//!
//! Official mode, as Codenotch reads it: the session Codex keeps in
//! ~/.codex/auth.json (`tokens.access_token`, `tokens.account_id`) against
//!
//! ```text
//! GET https://chatgpt.com/backend-api/wham/usage
//! ```
//!
//! whose `rate_limit.{primary_window,secondary_window}` carry `used_percent`,
//! `limit_window_seconds` and `reset_at`. Spark and code review limits come
//! back beside them and go on the card under their own headings. The token is
//! read only, never refreshed or written: a 401/403 means Codex has to be
//! opened once.
//!
//! The fallback, and all of local mode, is what Codex wrote into its rollout
//! logs, ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl, in `token_count` events:
//!
//! ```text
//! payload.info.total_token_usage.total_tokens
//! payload.rate_limits.{primary,secondary}.{used_percent, window_minutes, resets_at}
//! ```
//!
//! That is the number from the last run, so it stands as current only while
//! the line is under five minutes old.

use std::path::{Path, PathBuf};

use anyhow::Result;
use base64::Engine;
use serde_json::Value;

use crate::config::DataMode;
use crate::http::{self, HttpError};
use crate::store::Saved;
use crate::{
    CURRENT_FOR_SECS, Config, Fetch, ProviderUsage, SOURCE_LOCAL, SOURCE_OFFICIAL, Status,
    UsageProvider, UsageWindow, err_parse, jsonl, paths,
};

const ID: &str = "codex";
const ENDPOINT: &str = "https://chatgpt.com/backend-api/wham/usage";
/// Codex has no session state to pace against, so a fixed five minutes.
const POLL_SECS: i64 = 300;
const BACKOFF_MIN_SECS: u64 = 60;
const NO_SNAPSHOT: &str = "Codex has not recorded a usage snapshot yet";

pub struct Codex {
    config: Config,
}

impl Codex {
    pub fn new(config: Config) -> Self {
        Self { config }
    }
}

impl UsageProvider for Codex {
    fn id(&self) -> &'static str {
        ID
    }

    fn fetch(&self, ctx: &Fetch) -> Result<ProviderUsage> {
        let home = paths::codex_home()?;
        if !home.exists() {
            return Ok(ProviderUsage::absent(ID));
        }

        let scan = scan_sessions(&home.join("sessions"), self.config.scan_cutoff_secs(), ctx.now);
        let mut usage = match self.config.data.mode {
            DataMode::Official => official(ctx, &home, &scan),
            DataMode::Local => {
                let mut usage = ProviderUsage::new(ID, SOURCE_LOCAL);
                if !apply_rollout(&mut usage, &scan, ctx.now) {
                    usage.note = Some(NO_SNAPSHOT.into());
                }
                usage
            }
        };

        usage.account = read_account(&home.join("auth.json"));
        usage.tokens_today = Some(scan.tokens);
        if let Some(err) = &scan.parse_error {
            usage.error = Some(err_parse(err));
        }
        usage.settle(ctx.now);
        Ok(usage)
    }
}

fn official(ctx: &Fetch, home: &Path, scan: &Scan) -> ProviderUsage {
    let now = ctx.now;
    let mut saved = Saved::load(ID);
    let mut note: Option<String> = None;
    let mut needs_auth = false;

    if let Some(until) = saved.backing_off(now) {
        note = Some(format!("Rate limited, retrying in {}s", until - now));
    } else if saved.due(now, POLL_SECS, ctx.force) {
        saved.last_attempt = Some(now);
        match read_live(&home.join("auth.json"), now) {
            Live::Reading(usage) => {
                saved.backoff_until = None;
                saved.usage = Some((*usage).clone());
                saved.save(ID);
                return *usage;
            }
            Live::NotSignedIn => {}
            Live::NeedsAuth(why) => {
                needs_auth = true;
                note = Some(why);
            }
            Live::RateLimited(secs) => {
                saved.backoff_until = Some(now.saturating_add(secs as i64));
                note = Some(format!("Rate limited, retrying in {secs}s"));
            }
            Live::Failed(why) => note = Some(why),
        }
    } else if let Some(last) = saved.usage.clone().filter(|u| {
        u.status == Status::Ok && u.fetched_at.is_some_and(|at| now - at <= POLL_SECS)
    }) {
        return last;
    }
    saved.save(ID);

    // Whichever is newer: the last live reading, or the rollout's own line.
    let last_live = saved.usage.clone().filter(|u| !u.windows.is_empty());
    let rollout_newer = scan
        .recorded_at
        .is_some_and(|at| last_live.as_ref().and_then(|u| u.fetched_at).is_none_or(|live| at >= live));

    let mut usage = ProviderUsage::new(ID, SOURCE_LOCAL);
    if (rollout_newer || last_live.is_none()) && apply_rollout(&mut usage, scan, now) {
        if let Some(why) = note {
            usage.note = Some(format!("{why} · from last Codex run"));
        }
    } else if let Some(mut last) = last_live {
        last.status = Status::Stale;
        last.note = note;
        usage = last;
    } else {
        usage.status = if needs_auth { Status::NeedsAuth } else { Status::None };
        usage.note = note.or_else(|| Some(NO_SNAPSHOT.into()));
    }
    usage.backoff_until = saved.backing_off(now);
    usage
}

enum Live {
    Reading(Box<ProviderUsage>),
    NotSignedIn,
    NeedsAuth(String),
    RateLimited(u64),
    Failed(String),
}

fn read_live(auth: &Path, now: i64) -> Live {
    let Some(credential) = load_credential(auth, now) else {
        return Live::NotSignedIn;
    };
    let bearer = format!("Bearer {}", credential.access_token);
    let reply = http::get_json(
        ENDPOINT,
        &[
            ("Authorization", bearer.as_str()),
            ("ChatGPT-Account-Id", credential.account_id.as_str()),
            ("Accept", "application/json"),
            ("Cache-Control", "no-cache, no-store"),
        ],
    );
    match reply {
        Ok(reply) => {
            let windows = windows_from_usage(&reply, now);
            if windows.is_empty() {
                return Live::Failed("Codex reported no usage windows".into());
            }
            let mut usage = ProviderUsage::new(ID, SOURCE_OFFICIAL);
            usage.status = Status::Ok;
            usage.headline = windows.first().map(|w| w.id.clone());
            usage.windows = windows;
            usage.fetched_at = Some(now);
            usage.plan = reply
                .get("plan_type")
                .and_then(Value::as_str)
                .map(str::to_string)
                .or(credential.plan);
            Live::Reading(Box::new(usage))
        }
        Err(HttpError::Status { code: 401 | 403, .. }) => Live::NeedsAuth(if credential.expired {
            "Codex sign-in expired — open Codex once to refresh it".into()
        } else {
            "Codex rejected its sign-in — sign in to Codex again".into()
        }),
        Err(HttpError::Status { code: 429, retry_after }) => {
            Live::RateLimited(retry_after.unwrap_or(0).max(BACKOFF_MIN_SECS))
        }
        Err(err) => Live::Failed(format!("Live read failed ({err})")),
    }
}

struct Credential {
    access_token: String,
    account_id: String,
    plan: Option<String>,
    /// Still sent, the server decides; this only picks the wording of a 401.
    expired: bool,
}

fn load_credential(path: &Path, now: i64) -> Option<Credential> {
    let text = std::fs::read_to_string(path).ok()?;
    let value: Value = serde_json::from_str(&text).ok()?;
    let tokens = value.get("tokens")?;
    let access_token = tokens.get("access_token")?.as_str()?.trim().to_string();
    let account_id = tokens.get("account_id")?.as_str()?.trim().to_string();
    if access_token.is_empty() || account_id.is_empty() {
        return None;
    }
    let expired = jwt_claims(&access_token)
        .and_then(|claims| claims.get("exp").and_then(Value::as_f64))
        .is_some_and(|exp| exp <= now as f64);
    let plan = tokens
        .get("id_token")
        .and_then(Value::as_str)
        .and_then(jwt_claims)
        .and_then(|claims| {
            claims
                .get("https://api.openai.com/auth")?
                .get("chatgpt_plan_type")?
                .as_str()
                .map(str::to_string)
        });
    Some(Credential { access_token, account_id, plan, expired })
}

/// A JWT's claims, decoded locally for labels and an expiry hint. Nothing is
/// verified here; that is the server's job.
fn jwt_claims(token: &str) -> Option<Value> {
    let payload = token.split('.').nth(1)?;
    let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(payload.trim_end_matches('='))
        .ok()?;
    serde_json::from_slice(&bytes).ok()
}

// ---------------- the live reply ----------------

/// Primary and secondary feed the ring; Spark and code review belong on the
/// card, grouped. The label comes from the window's length, because the
/// primary window is not always five hours.
fn windows_from_usage(reply: &Value, now: i64) -> Vec<UsageWindow> {
    let mut out = Vec::new();
    for (slot, key) in [("primary", "primary_window"), ("secondary", "secondary_window")] {
        if let Some(window) = reply
            .pointer(&format!("/rate_limit/{key}"))
            .and_then(|w| live_window(w, slot, slot, now))
        {
            out.push(window);
        }
    }
    // A non-array is the same as the field being absent: one junk extra must
    // not cost the main pair.
    if let Some(extras) = reply.get("additional_rate_limits").and_then(Value::as_array) {
        for extra in extras.iter().filter(|extra| names_spark(extra)) {
            append_extra(extra.get("rate_limit"), "spark", "Spark", now, &mut out);
        }
    }
    append_extra(reply.get("code_review_rate_limit"), "code-review", "Code review", now, &mut out);
    out
}

fn live_window(window: &Value, id: &str, slot: &str, now: i64) -> Option<UsageWindow> {
    if !window.is_object() {
        return None;
    }
    let used = window.get("used_percent").and_then(Value::as_f64)?;
    let minutes = window
        .get("limit_window_seconds")
        .and_then(Value::as_f64)
        .filter(|secs| secs.is_finite() && *secs > 0.0)
        .map(|secs| (secs / 60.0) as i64);
    let resets_at = seconds(window.get("reset_at"))
        .or_else(|| seconds(window.get("reset_after_seconds")).map(|delay| now.saturating_add(delay)));
    Some(UsageWindow::new(
        id,
        UsageWindow::label_for_minutes(minutes, slot),
        used,
        minutes,
        resets_at,
    ))
}

/// Negative, non-finite or absurd values count as missing, so a garbage field
/// cannot push a reset past the end of time.
fn seconds(value: Option<&Value>) -> Option<i64> {
    value
        .and_then(Value::as_f64)
        .filter(|secs| secs.is_finite() && *secs >= 0.0 && *secs < 1e12)
        .map(|secs| secs as i64)
}

fn names_spark(extra: &Value) -> bool {
    extra.is_object()
        && ["limit_name", "metered_feature"].iter().any(|key| {
            extra
                .get(*key)
                .and_then(Value::as_str)
                .is_some_and(|name| name.to_lowercase().contains("spark"))
        })
}

fn append_extra(limits: Option<&Value>, id: &str, group: &str, now: i64, out: &mut Vec<UsageWindow>) {
    let Some(limits) = limits.filter(|l| l.is_object()) else { return };
    for (suffix, slot, key) in [("", "primary", "primary_window"), ("-secondary", "secondary", "secondary_window")] {
        let window_id = format!("{id}{suffix}");
        if out.iter().any(|w| w.id == window_id) {
            continue;
        }
        if let Some(window) = limits.get(key).and_then(|w| live_window(w, &window_id, slot, now)) {
            out.push(window.grouped(group));
        }
    }
}

// ---------------- the rollout logs ----------------

#[derive(Default)]
struct Scan {
    tokens: u64,
    windows: Vec<UsageWindow>,
    /// The timestamp of the line the windows came from.
    recorded_at: Option<i64>,
    plan: Option<String>,
    parse_error: Option<String>,
}

fn apply_rollout(usage: &mut ProviderUsage, scan: &Scan, now: i64) -> bool {
    if scan.windows.is_empty() {
        return false;
    }
    usage.source = SOURCE_LOCAL.into();
    usage.windows = scan.windows.clone();
    usage.headline = usage.windows.first().map(|w| w.id.clone());
    usage.fetched_at = scan.recorded_at;
    usage.plan = scan.plan.clone();
    usage.status = if scan.recorded_at.is_some_and(|at| now - at <= CURRENT_FOR_SECS) {
        Status::Ok
    } else {
        Status::Stale
    };
    usage.note = Some("from last Codex run".into());
    true
}

/// Walk the rollout logs, newest first.
///
/// Tokens count only from logs touched at or after `cutoff_secs`, each file
/// contributing the last cumulative total it recorded. Limits are not bound by
/// that cutoff: a 30 day window read from a week-old log is still the account's
/// last known state, so older logs are read until one carries limits.
fn scan_sessions(sessions: &Path, cutoff_secs: i64, now: i64) -> Scan {
    let mut scan = Scan::default();
    let mut newest: Option<(i64, Vec<UsageWindow>, Option<String>)> = None;

    let mut files: Vec<(PathBuf, Option<i64>)> = paths::collect_files(sessions, "jsonl")
        .into_iter()
        .map(|path| {
            let mtime = paths::mtime_secs(&path);
            (path, mtime)
        })
        .collect();
    files.sort_by_key(|(_, mtime)| std::cmp::Reverse(*mtime));

    for (path, mtime) in files {
        let fresh = mtime.is_none_or(|mtime| mtime >= cutoff_secs);
        if !fresh && newest.is_some() {
            break;
        }

        let mut file_tokens: Option<u64> = None;
        let result = jsonl::for_each(&path, |value| {
            if value.pointer("/payload/type").and_then(Value::as_str) != Some("token_count") {
                return;
            }
            if let Some(total) = value
                .pointer("/payload/info/total_token_usage/total_tokens")
                .and_then(Value::as_u64)
            {
                file_tokens = Some(total);
            }
            let Some(limits) = value.pointer("/payload/rate_limits").filter(|l| l.is_object()) else {
                return;
            };
            let windows = rollout_windows(limits, now);
            if windows.is_empty() {
                return;
            }
            let at = value
                .get("timestamp")
                .and_then(Value::as_str)
                .and_then(crate::time::rfc3339_to_unix)
                .unwrap_or_default();
            if newest.as_ref().is_none_or(|(seen, _, _)| at >= *seen) {
                let plan = limits.get("plan_type").and_then(Value::as_str).map(str::to_string);
                newest = Some((at, windows, plan));
            }
        });

        match result {
            Ok(()) if fresh => scan.tokens = scan.tokens.saturating_add(file_tokens.unwrap_or_default()),
            Ok(()) => {}
            Err(err) => {
                if scan.parse_error.is_none() {
                    scan.parse_error = Some(format!("{err:#}"));
                }
            }
        }
    }

    if let Some((at, windows, plan)) = newest {
        scan.recorded_at = (at > 0).then_some(at);
        scan.windows = windows;
        scan.plan = plan;
    }
    scan
}

fn rollout_windows(limits: &Value, now: i64) -> Vec<UsageWindow> {
    ["primary", "secondary"]
        .into_iter()
        .filter_map(|slot| {
            let block = limits.get(slot).filter(|b| b.is_object())?;
            let used = block.get("used_percent").and_then(Value::as_f64)?;
            let minutes = block.get("window_minutes").and_then(Value::as_i64);
            let resets_at = seconds(block.get("resets_at"))
                .or_else(|| seconds(block.get("resets_in_seconds")).map(|delay| now.saturating_add(delay)));
            Some(UsageWindow::new(
                slot,
                UsageWindow::label_for_minutes(minutes, slot),
                used,
                minutes,
                resets_at,
            ))
        })
        .collect()
}

/// The account email is a claim inside the stored id token, decoded locally.
fn read_account(auth_path: &Path) -> Option<String> {
    let text = std::fs::read_to_string(auth_path).ok()?;
    let value: Value = serde_json::from_str(&text).ok()?;
    let id_token = value.pointer("/tokens/id_token").and_then(Value::as_str)?;
    jwt_claims(id_token)?
        .get("email")
        .and_then(Value::as_str)
        .map(str::to_string)
}

/// For `flare doctor`. Never prints a secret.
pub fn probe() -> Vec<String> {
    let now = paths::now_secs();
    let mut lines = Vec::new();
    let Ok(home) = paths::codex_home() else {
        return vec!["home: unresolved".into()];
    };
    let auth = home.join("auth.json");
    lines.push(match load_credential(&auth, now) {
        Some(credential) => format!(
            "sign-in: usable{}{}",
            if credential.expired { " (access token expired)" } else { "" },
            credential.plan.map(|p| format!(", plan {p}")).unwrap_or_default()
        ),
        None if auth.is_file() => "sign-in: auth.json has no usable token".into(),
        None => format!("sign-in: NOT FOUND ({})", auth.display()),
    });
    let scan = scan_sessions(&home.join("sessions"), i64::MAX, now);
    lines.push(match scan.recorded_at {
        Some(at) => format!("newest rollout limits: recorded {}m ago", (now - at) / 60),
        None => "newest rollout limits: none".into(),
    });
    lines
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::{NO_CUTOFF, fixture};
    use serde_json::json;

    /// Before every reset time in the fixtures.
    const FIXTURE_NOW: i64 = 1_787_000_000;

    fn ids(windows: &[UsageWindow]) -> Vec<&str> {
        windows.iter().map(|w| w.id.as_str()).collect()
    }

    #[test]
    fn takes_the_last_cumulative_total_per_session() {
        let scan = scan_sessions(&fixture("codex/sessions_ok"), NO_CUTOFF, FIXTURE_NOW);
        assert_eq!(scan.tokens, 5000);
        assert!(scan.parse_error.is_none());
    }

    #[test]
    fn labels_rollout_windows_by_length() {
        let scan = scan_sessions(&fixture("codex/sessions_ok"), NO_CUTOFF, FIXTURE_NOW);
        assert_eq!(ids(&scan.windows), ["primary", "secondary"]);
        assert_eq!(scan.windows[0].label, "Weekly limit");
        assert_eq!(scan.windows[1].label, "5h limit");
        assert!((scan.windows[0].used - 0.93).abs() < 1e-9);
        assert!((scan.windows[1].used - 0.40).abs() < 1e-9);
        assert_eq!(scan.plan.as_deref(), Some("plus"));
        assert!(scan.recorded_at.is_some());
    }

    #[test]
    fn rollout_limits_outlive_the_token_scan_window() {
        let scan = scan_sessions(&fixture("codex/sessions_ok"), i64::MAX, FIXTURE_NOW);
        assert_eq!(scan.tokens, 0);
        assert_eq!(scan.windows.len(), 2);
    }

    #[test]
    fn a_truncated_final_line_does_not_lose_the_session_total() {
        let scan = scan_sessions(&fixture("codex/sessions_truncated"), NO_CUTOFF, FIXTURE_NOW);
        assert_eq!(scan.tokens, 5000);
        assert!(scan.parse_error.is_none());
    }

    #[test]
    fn damage_on_an_earlier_line_surfaces_as_a_parse_error() {
        let scan = scan_sessions(&fixture("codex/sessions_malformed"), NO_CUTOFF, FIXTURE_NOW);
        assert!(scan.parse_error.is_some());
    }

    #[test]
    fn a_missing_sessions_dir_yields_nothing_and_no_error() {
        let scan = scan_sessions(&fixture("codex/no_such_dir"), NO_CUTOFF, FIXTURE_NOW);
        assert_eq!(scan.tokens, 0);
        assert!(scan.windows.is_empty());
        assert!(scan.parse_error.is_none());
    }

    #[test]
    fn live_extras_follow_the_main_pair_in_their_own_groups() {
        let windows = windows_from_usage(
            &json!({
                "rate_limit": {
                    "primary_window": {"used_percent": 25, "limit_window_seconds": 18000, "reset_at": 1800001000},
                    "secondary_window": {"used_percent": 10, "limit_window_seconds": 604800, "reset_at": 1800600000}},
                "additional_rate_limits": [
                    "junk", null,
                    {"limit_name": "GPT-5.3-Codex-SPARK", "rate_limit": {
                        "primary_window": {"used_percent": 99, "limit_window_seconds": 18000}}},
                    {"limit_name": "codex_other", "rate_limit": {
                        "primary_window": {"used_percent": 70, "limit_window_seconds": 3600}}}],
                "code_review_rate_limit": {"primary_window": {"used_percent": 90, "limit_window_seconds": 604800}}
            }),
            FIXTURE_NOW,
        );
        assert_eq!(ids(&windows), ["primary", "secondary", "spark", "code-review"]);
        let labels: Vec<&str> = windows.iter().map(|w| w.label.as_str()).collect();
        assert_eq!(labels, ["5h limit", "Weekly limit", "5h limit", "Weekly limit"]);
        let groups: Vec<Option<&str>> = windows.iter().map(|w| w.group.as_deref()).collect();
        assert_eq!(groups, [None, None, Some("Spark"), Some("Code review")]);
        assert_eq!(windows[0].resets_at, Some(1_800_001_000));
    }

    #[test]
    fn a_monthly_primary_is_kept_and_named() {
        let windows = windows_from_usage(
            &json!({"rate_limit": {"primary_window": {"used_percent": 16, "limit_window_seconds": 2592000,
                "reset_after_seconds": 100}, "secondary_window": null}}),
            FIXTURE_NOW,
        );
        assert_eq!(ids(&windows), ["primary"]);
        assert_eq!(windows[0].label, "Monthly limit");
        assert_eq!(windows[0].resets_at, Some(FIXTURE_NOW + 100));
    }

    #[test]
    fn an_absurd_reset_delay_is_dropped_rather_than_overflowing() {
        let windows = windows_from_usage(
            &json!({"rate_limit": {"primary_window": {"used_percent": 5, "reset_after_seconds": 1e20}}}),
            FIXTURE_NOW,
        );
        assert_eq!(windows[0].resets_at, None);
    }

    #[test]
    fn reads_the_sign_in_without_verifying_it() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("auth.json");
        let claims = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(r#"{"exp":100}"#);
        std::fs::write(
            &path,
            format!(r#"{{"tokens":{{"access_token":"h.{claims}.s","account_id":"acct"}}}}"#),
        )
        .unwrap();
        let credential = load_credential(&path, 200).expect("credential");
        assert_eq!(credential.account_id, "acct");
        assert!(credential.expired);

        std::fs::write(&path, r#"{"tokens":{"access_token":"x","account_id":" "}}"#).unwrap();
        assert!(load_credential(&path, 200).is_none());
    }

    #[test]
    fn labels_the_account_from_the_id_token_claim() {
        let account = read_account(&fixture("codex/auth_ok.json"));
        assert_eq!(account.as_deref(), Some("redacted@example.invalid"));
        assert!(read_account(&fixture("codex/no_such_auth.json")).is_none());
    }
}
