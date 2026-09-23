//! Antigravity CLI (`agy`) provider (local in both modes).
//!
//! agy keeps one sqlite database per conversation, at
//! ~/.gemini/antigravity-cli/conversations/<id>.db. Its rows hold protobuf
//! messages with no published schema; the fields read here were matched
//! against real databases with `protoc --decode_raw`:
//!
//! - `steps.metadata`: field 1 is the step's creation time (a Timestamp,
//!   seconds in its field 1) and field 9, on each model reply, its usage:
//!   1 input, 2 cached input, 3 output. Output is itself thinking (9) plus
//!   the reply (10), which held on every reply checked, so 1 + 2 + 3 is the
//!   whole reply once. `gen_metadata` repeats the same usage without a time.
//! - `trajectory_metadata_blob.data`: field 1 is the workspace, its URI in
//!   field 1; field 2 is when the conversation started.
//!
//! Quotas are never written to disk: agy keeps them in memory and hands them
//! to its status line command. hooks/agy-statusline-capture.sh saves that
//! payload as $XDG_STATE_HOME/flare/agy-statusline.json, whose `quota` holds
//! one bucket per model group, as a real capture showed:
//!
//! ```text
//! "quota": { "gemini-weekly": { "remaining_fraction": 0.98, "reset_time": "…Z" },
//!            "3p-weekly":     { "remaining_fraction": 1,    "reset_time": "…Z" } }
//! "plan_tier": "Antigravity Starter Quota"
//! ```
//!
//! Each bucket becomes a window. Without a capture the widget shows today's
//! tokens instead of a percentage.

use std::path::{Path, PathBuf};

use anyhow::Result;
use rusqlite::{Connection, OpenFlags, OptionalExtension};
use serde_json::Value;

use crate::sessions::{self, Logged};
use crate::{
    Activity, Config, Fetch, ProviderUsage, Reply, SOURCE_LOCAL, Status, Unit, UsageProvider, UsageWindow,
    err_parse, paths, proto, time,
};

const ID: &str = "antigravity";

pub struct Antigravity {
    config: Config,
}

impl Antigravity {
    pub fn new(config: Config) -> Self {
        Self { config }
    }
}

impl UsageProvider for Antigravity {
    fn id(&self) -> &'static str {
        ID
    }

    fn fetch(&self, ctx: &Fetch) -> Result<ProviderUsage> {
        let home = paths::antigravity_home()?;
        if !home.exists() {
            return Ok(ProviderUsage::absent(ID));
        }

        let mut usage = ProviderUsage::new(ID, SOURCE_LOCAL);
        usage.status = Status::Ok;
        match read_capture() {
            Some(capture) if !capture.windows.is_empty() => {
                usage.headline = capture
                    .windows
                    .iter()
                    .max_by(|a, b| a.used.total_cmp(&b.used))
                    .map(|w| w.id.clone());
                usage.windows = capture.windows;
                // A quota moves only while agy runs, and every run rewrites the
                // capture: however old, it is what agy would say now.
                usage.fetched_at = Some(ctx.now);
                usage.plan = capture.plan;
                usage.note = capture.captured_at.map(|at| {
                    format!("from agy's status line, {}m ago", (ctx.now - at).max(0) / 60)
                });
            }
            _ => {
                usage.metered = false;
                usage.note = Some(
                    "Point agy's statusLine at hooks/agy-statusline-capture.sh to see its quotas".into(),
                );
            }
        }

        let cutoff = self.config.scan_cutoff_secs();
        let scan = scan(&home.join("conversations"), cutoff);
        usage.tokens_today = Some(
            scan.conversations
                .iter()
                .flat_map(|c| &c.replies)
                .filter(|(at, _)| *at >= cutoff)
                .map(|(_, tokens)| tokens)
                .sum(),
        );
        usage.error = scan.error.map(err_parse);
        usage.settle(ctx.now);
        Ok(usage)
    }

    fn activity(&self, cutoff_secs: i64) -> Option<Activity> {
        let home = paths::antigravity_home().ok()?;
        let replies = scan(&home.join("conversations"), cutoff_secs)
            .conversations
            .into_iter()
            .flat_map(|c| c.replies.into_iter().zip(c.models))
            .filter(|((at, _), _)| *at >= cutoff_secs)
            .map(|((at, tokens), model)| Reply { at, amount: tokens as f64, model });
        Some(Activity::from_replies(Unit::Tokens, replies))
    }

    fn session_log(&self, now: i64) -> Option<Vec<Logged>> {
        let home = paths::antigravity_home().ok()?;
        let since = now - sessions::LOG_KEEP_SECS;
        let mut log: Vec<Logged> = scan(&home.join("conversations"), since)
            .conversations
            .into_iter()
            .filter_map(|c| {
                let last = c.replies.iter().map(|(at, _)| *at).max()?;
                let first = c.started.or_else(|| c.replies.iter().map(|(at, _)| *at).min())?;
                let project = c.workspace.as_deref().map(workspace_name).unwrap_or_default();
                (last >= since).then(|| Logged::from_history(String::new(), project, first, last, now))
            })
            .collect();
        log.sort_by_key(|entry| entry.started_at);
        Some(log)
    }
}

struct Capture {
    windows: Vec<UsageWindow>,
    captured_at: Option<i64>,
    plan: Option<String>,
}

fn capture_path() -> Option<PathBuf> {
    paths::flare_state().ok().map(|dir| dir.join("agy-statusline.json"))
}

/// The last status line agy handed the capture hook, timed by the file.
fn read_capture() -> Option<Capture> {
    let path = capture_path()?;
    let value: Value = serde_json::from_str(&std::fs::read_to_string(&path).ok()?).ok()?;
    Some(Capture {
        windows: quota_windows(&value),
        captured_at: paths::mtime_secs(&path),
        plan: value.get("plan_tier").and_then(Value::as_str).map(str::to_string),
    })
}

/// One window per quota bucket, the fullest first.
fn quota_windows(payload: &Value) -> Vec<UsageWindow> {
    let Some(buckets) = payload.get("quota").and_then(Value::as_object) else {
        return Vec::new();
    };
    let mut out: Vec<UsageWindow> = buckets
        .iter()
        .filter_map(|(name, bucket)| {
            let remaining = bucket.get("remaining_fraction").and_then(Value::as_f64)?;
            let resets_at = bucket.get("reset_time").and_then(Value::as_str).and_then(time::rfc3339_to_unix);
            let (family, minutes) = split_bucket(name);
            let used = (1.0 - remaining).clamp(0.0, 1.0) * 100.0;
            Some(UsageWindow::new(name, family, used, minutes, resets_at))
        })
        .collect();
    out.sort_by(|a, b| b.used.total_cmp(&a.used).then_with(|| a.id.cmp(&b.id)));
    out
}

/// `gemini-weekly` → ("Gemini models", 7 days); `3p-weekly` is every model
/// that is not Google's own.
fn split_bucket(name: &str) -> (String, Option<i64>) {
    let (family, period) = name.rsplit_once('-').unwrap_or((name, ""));
    let minutes = match period {
        "weekly" => Some(10_080),
        "daily" => Some(1_440),
        "5h" => Some(300),
        "hourly" => Some(60),
        _ => None,
    };
    let family = if minutes.is_none() { name } else { family };
    let label = match family {
        "gemini" => "Gemini models".to_string(),
        "3p" => "Other models".to_string(),
        other => {
            let mut chars = other.chars();
            chars.next().map(|c| c.to_uppercase().collect::<String>() + chars.as_str()).unwrap_or_default()
        }
    };
    (label, minutes)
}

#[derive(Default)]
struct Conversation {
    workspace: Option<String>,
    started: Option<i64>,
    /// Each model reply as (unix seconds, tokens).
    replies: Vec<(i64, u64)>,
    /// The model behind each reply, where `gen_metadata` names it; same order.
    models: Vec<Option<String>>,
}

#[derive(Default)]
struct Scan {
    conversations: Vec<Conversation>,
    error: Option<String>,
}

/// Every conversation written to since `cutoff_secs`. A database untouched
/// since then is not opened. The first failure is kept, and the rest are
/// still read.
fn scan(dir: &Path, cutoff_secs: i64) -> Scan {
    let mut scan = Scan::default();
    for path in databases(dir) {
        if last_written(&path).is_some_and(|at| at < cutoff_secs) {
            continue;
        }
        match read_conversation(&path) {
            Ok(conversation) => scan.conversations.push(conversation),
            Err(err) => {
                scan.error.get_or_insert_with(|| format!("{}: {err:#}", path.display()));
            }
        }
    }
    scan
}

fn databases(dir: &Path) -> Vec<PathBuf> {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return Vec::new();
    };
    entries
        .flatten()
        .filter(|entry| entry.file_type().is_ok_and(|t| t.is_file()))
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "db"))
        .collect()
}

/// A database in WAL mode may have its newest pages only in the -wal file.
fn last_written(db: &Path) -> Option<i64> {
    let mut wal = db.as_os_str().to_owned();
    wal.push("-wal");
    [paths::mtime_secs(db), paths::mtime_secs(Path::new(&wal))].into_iter().flatten().max()
}

fn read_conversation(path: &Path) -> Result<Conversation> {
    let uri = format!("file:{}?mode=ro", path.display());
    let conn = Connection::open_with_flags(&uri, OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_URI)?;

    let mut conversation = Conversation::default();
    let trajectory: Option<Vec<u8>> = conn
        .query_row("SELECT data FROM trajectory_metadata_blob LIMIT 1", [], |row| row.get(0))
        .optional()?;
    if let Some(blob) = trajectory {
        conversation.workspace = proto::message(&blob, 1)
            .and_then(|workspace| proto::message(workspace, 1))
            .map(|uri| String::from_utf8_lossy(uri).into_owned());
        conversation.started = proto::message(&blob, 2)
            .and_then(|time| proto::varint(time, 1))
            .and_then(|secs| i64::try_from(secs).ok());
    }

    let names = models_by_usage(&conn);
    let mut statement = conn.prepare("SELECT metadata FROM steps WHERE metadata IS NOT NULL")?;
    let blobs = statement.query_map([], |row| row.get::<_, Vec<u8>>(0))?;
    for blob in blobs {
        let blob = blob?;
        if let Some(reply) = reply(&blob) {
            conversation.models.push(usage_key(&blob, 9).and_then(|key| names.get(&key).cloned()));
            conversation.replies.push(reply);
        }
    }
    Ok(conversation)
}

/// A step's usage block and the generation that made it carry the same
/// counts, which is how a reply finds its model: `gen_metadata` names the
/// model (field 1.19) beside that usage (field 1.4), but has no time.
fn models_by_usage(conn: &Connection) -> std::collections::HashMap<[u64; 3], String> {
    let mut out = std::collections::HashMap::new();
    let Ok(mut statement) = conn.prepare("SELECT data FROM gen_metadata") else {
        return out;
    };
    let Ok(rows) = statement.query_map([], |row| row.get::<_, Vec<u8>>(0)) else {
        return out;
    };
    for data in rows.flatten() {
        let Some(generation) = proto::message(&data, 1) else { continue };
        let Some(key) = usage_key(generation, 4) else { continue };
        if let Some(model) = proto::message(generation, 19).map(|m| String::from_utf8_lossy(m).into_owned()) {
            out.insert(key, model);
        }
    }
    out
}

fn usage_key(message: &[u8], field: u64) -> Option<[u64; 3]> {
    let usage = proto::message(message, field)?;
    Some([1, 2, 3].map(|f| proto::varint(usage, f).unwrap_or(0)))
}

/// A step's (time, tokens), or None for a step that is not a model reply.
fn reply(metadata: &[u8]) -> Option<(i64, u64)> {
    let usage = proto::message(metadata, 9)?;
    let at = proto::message(metadata, 1).and_then(|time| proto::varint(time, 1))?;
    let tokens = [1, 2, 3]
        .into_iter()
        .filter_map(|field| proto::varint(usage, field))
        .fold(0u64, u64::saturating_add);
    Some((i64::try_from(at).ok()?, tokens))
}

/// `file:///home/u/project` → `project`.
fn workspace_name(uri: &str) -> String {
    sessions::folder_name(uri.strip_prefix("file://").unwrap_or(uri))
}

/// For `flare doctor`.
pub fn probe() -> Vec<String> {
    let mut lines = probe_conversations();
    let capture = capture_path();
    lines.push(match capture.as_deref().and_then(paths::mtime_secs) {
        Some(at) => format!("quota capture: found, written {}s ago", paths::now_secs() - at),
        None => "quota capture: none — point agy's statusLine at hooks/agy-statusline-capture.sh".into(),
    });
    lines
}

fn probe_conversations() -> Vec<String> {
    match paths::antigravity_home() {
        Ok(home) => {
            let dir = home.join("conversations");
            let found = databases(&dir);
            match found.iter().filter_map(|db| last_written(db)).max() {
                Some(at) => vec![format!(
                    "conversations: {} found ({}), last written {}s ago",
                    found.len(),
                    dir.display(),
                    paths::now_secs() - at
                )],
                None if home.exists() => vec![format!("conversations: none yet ({})", dir.display())],
                None => vec![format!("directory: NOT FOUND ({}) — not installed", home.display())],
            }
        }
        Err(err) => vec![format!("home: unresolved ({err:#})")],
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::NO_CUTOFF;

    fn varint(mut value: u64, out: &mut Vec<u8>) {
        loop {
            let byte = (value & 0x7f) as u8;
            value >>= 7;
            if value == 0 {
                out.push(byte);
                return;
            }
            out.push(byte | 0x80);
        }
    }

    fn field_varint(number: u64, value: u64, out: &mut Vec<u8>) {
        varint(number << 3, out);
        varint(value, out);
    }

    fn field_bytes(number: u64, bytes: &[u8], out: &mut Vec<u8>) {
        varint(number << 3 | 2, out);
        varint(bytes.len() as u64, out);
        out.extend_from_slice(bytes);
    }

    fn timestamp(secs: u64) -> Vec<u8> {
        let mut out = Vec::new();
        field_varint(1, secs, &mut out);
        field_varint(2, 123_456, &mut out);
        out
    }

    /// A step's metadata as agy writes it; `usage` is (input, cached, thinking, reply).
    fn step(at: u64, usage: Option<(u64, u64, u64, u64)>) -> Vec<u8> {
        let mut out = Vec::new();
        field_bytes(1, &timestamp(at), &mut out);
        field_varint(3, 2, &mut out);
        if let Some((input, cached, thinking, answer)) = usage {
            let mut u = Vec::new();
            field_varint(1, input, &mut u);
            field_varint(2, cached, &mut u);
            field_varint(3, thinking + answer, &mut u);
            field_varint(6, 24, &mut u);
            field_varint(9, thinking, &mut u);
            field_varint(10, answer, &mut u);
            field_bytes(9, &u, &mut out);
        }
        out
    }

    fn conversation(dir: &Path, name: &str, workspace: &str, steps: &[Vec<u8>]) -> PathBuf {
        let path = dir.join(format!("{name}.db"));
        let conn = Connection::open(&path).expect("create test database");
        conn.execute_batch(
            "CREATE TABLE steps (idx integer PRIMARY KEY, step_type integer, metadata blob);
             CREATE TABLE gen_metadata (idx integer PRIMARY KEY, data blob);
             CREATE TABLE trajectory_metadata_blob (id text PRIMARY KEY, data blob);",
        )
        .expect("schema");
        for (index, metadata) in steps.iter().enumerate() {
            conn.execute("INSERT INTO steps VALUES (?1, 15, ?2)", rusqlite::params![index as i64, metadata])
                .expect("step");
        }
        // Name the model of the first reply with usage, the way agy does.
        if let Some(usage) = steps.iter().find_map(|s| proto::message(s, 9).map(<[u8]>::to_vec)) {
            let mut generation = Vec::new();
            field_bytes(4, &usage, &mut generation);
            field_bytes(19, b"gemini-3.8-flash", &mut generation);
            let mut data = Vec::new();
            field_bytes(1, &generation, &mut data);
            conn.execute("INSERT INTO gen_metadata VALUES (0, ?1)", [data]).expect("gen");
        }
        let mut meta = Vec::new();
        let mut ws = Vec::new();
        field_bytes(1, workspace.as_bytes(), &mut ws);
        field_bytes(1, &ws, &mut meta);
        field_bytes(2, &timestamp(1_000), &mut meta);
        conn.execute("INSERT INTO trajectory_metadata_blob VALUES ('main', ?1)", [meta]).expect("meta");
        path
    }

    #[test]
    fn counts_each_reply_once_and_skips_other_steps() {
        let dir = tempfile::tempdir().expect("temp dir");
        let path = conversation(
            dir.path(),
            "a",
            "file:///home/u/pclock",
            &[step(1_000, None), step(1_010, Some((1318, 14359, 576, 45))), step(4_000, Some((10, 0, 0, 5)))],
        );
        let c = read_conversation(&path).expect("conversation");
        assert_eq!(c.replies, vec![(1_010, 16_298), (4_000, 15)]);
        assert_eq!(c.models, vec![Some("gemini-3.8-flash".to_string()), None]);
        assert_eq!(c.workspace.as_deref(), Some("file:///home/u/pclock"));
        assert_eq!(c.started, Some(1_000));
    }

    #[test]
    fn a_database_of_another_shape_is_reported_not_fatal() {
        let dir = tempfile::tempdir().expect("temp dir");
        conversation(dir.path(), "good", "file:///home/u/x", &[step(2_000, Some((1, 2, 3, 4)))]);
        Connection::open(dir.path().join("odd.db"))
            .expect("create")
            .execute_batch("CREATE TABLE unrelated (x integer);")
            .expect("seed");
        let scan = scan(dir.path(), NO_CUTOFF);
        assert_eq!(scan.conversations.len(), 1);
        assert!(scan.error.is_some_and(|e| e.contains("odd.db")));
    }

    #[test]
    fn each_quota_bucket_is_a_window_fullest_first() {
        let payload: Value = serde_json::from_str(
            r#"{"quota":{
                 "3p-weekly":{"remaining_fraction":1,"reset_time":"2026-09-29T23:16:24Z","reset_in_seconds":604799},
                 "gemini-weekly":{"remaining_fraction":0.75,"reset_time":"2026-09-29T23:12:26Z","reset_in_seconds":604561}},
               "plan_tier":"Antigravity Starter Quota"}"#,
        )
        .unwrap();
        let windows = quota_windows(&payload);
        assert_eq!(windows.len(), 2);
        assert_eq!((windows[0].id.as_str(), windows[0].label.as_str()), ("gemini-weekly", "Gemini models"));
        assert!((windows[0].used - 0.25).abs() < 1e-9);
        assert_eq!(windows[0].window_minutes, Some(10_080));
        assert_eq!(windows[0].resets_at, time::rfc3339_to_unix("2026-09-29T23:12:26Z"));
        assert_eq!(windows[1].label, "Other models");
        assert_eq!(windows[1].used, 0.0);
    }

    #[test]
    fn an_unknown_bucket_keeps_its_name() {
        assert_eq!(split_bucket("gemini-5h"), ("Gemini models".to_string(), Some(300)));
        assert_eq!(split_bucket("flash"), ("Flash".to_string(), None));
        assert!(quota_windows(&serde_json::json!({ "quota": { "x": { "reset_time": "z" } } })).is_empty());
    }

    #[test]
    fn names_a_session_after_its_workspace() {
        assert_eq!(workspace_name("file:///home/u/settingwidgetrefactor"), "settingwidgetrefactor");
        assert_eq!(workspace_name("file:///home/u/"), "u");
    }
}
