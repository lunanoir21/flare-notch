//! Sessions running right now, read from what each CLI itself keeps on disk.
//!
//! Claude Code writes `<claude home>/sessions/<pid>.json` for every live
//! interactive session and keeps its `status` current. A file can outlive its
//! process (a crash, a kill -9), and a pid can be reused, so a session counts
//! only while `/proc/<pid>` exists and its start time still matches the
//! `procStart` the file recorded.

use std::fs;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::paths;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SessionState {
    /// Working on a turn.
    Busy,
    /// Stopped and asking the user for something.
    Waiting,
    /// Open, nothing happening.
    Idle,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub pid: u32,
    /// The session's own short name, or the project folder's when it has none.
    pub name: String,
    /// The last path component of the working directory.
    pub project: String,
    pub state: SessionState,
    /// What a waiting session is waiting for, in the CLI's own words.
    pub waiting_for: Option<String>,
    /// Unix seconds.
    pub started_at: Option<i64>,
}

/// Live sessions for a provider, oldest first. Providers with no known
/// per-session record report none rather than a guess.
///
/// On Hyprland a session also needs a window to count: a terminal host can
/// outlive its window (Orca's daemon keeps its shells running after the IDE
/// closes), and a session nobody can reach is as good as closed.
pub fn live(provider: &str) -> Vec<Session> {
    let found = match provider {
        "claude" => paths::claude_home()
            .map(|home| claude(&home.join("sessions"), Path::new("/proc")))
            .unwrap_or_default(),
        _ => Vec::new(),
    };
    if found.is_empty() {
        return found;
    }
    with_window(found, Path::new("/proc"), hypr_windows().as_deref())
}

/// Keeps the sessions that run under a window. With no window list (not on
/// Hyprland) there is nothing to judge by, so every session stays.
fn with_window(sessions: Vec<Session>, proc_root: &Path, windows: Option<&[(u32, String)]>) -> Vec<Session> {
    let Some(windows) = windows else {
        return sessions;
    };
    sessions
        .into_iter()
        .filter(|session| window_for(proc_root, session.pid, windows).is_some())
        .collect()
}

/// Every Hyprland window as (owning pid, address), or None off Hyprland.
fn hypr_windows() -> Option<Vec<(u32, String)>> {
    #[derive(Deserialize)]
    struct Client {
        pid: i64,
        address: String,
    }
    let output = std::process::Command::new("hyprctl").args(["clients", "-j"]).output().ok()?;
    if !output.status.success() {
        return None;
    }
    let clients: Vec<Client> = serde_json::from_slice(&output.stdout).ok()?;
    Some(
        clients
            .into_iter()
            .filter_map(|client| Some((u32::try_from(client.pid).ok()?, client.address)))
            .collect(),
    )
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ClaudeRecord {
    pid: u32,
    cwd: Option<String>,
    name: Option<String>,
    status: Option<String>,
    waiting_for: Option<String>,
    started_at: Option<i64>,
    proc_start: Option<String>,
}

fn claude(dir: &Path, proc_root: &Path) -> Vec<Session> {
    let Ok(entries) = fs::read_dir(dir) else {
        return Vec::new();
    };
    let mut out: Vec<Session> = entries
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "json"))
        .filter_map(|path| serde_json::from_str::<ClaudeRecord>(&fs::read_to_string(path).ok()?).ok())
        .filter(|record| alive(proc_root, record.pid, record.proc_start.as_deref()))
        .map(|record| {
            let project = record
                .cwd
                .as_deref()
                .and_then(|cwd| Path::new(cwd).file_name())
                .map(|name| name.to_string_lossy().into_owned())
                .unwrap_or_default();
            let state = match record.status.as_deref() {
                Some("busy") => SessionState::Busy,
                Some("waiting") => SessionState::Waiting,
                _ => SessionState::Idle,
            };
            Session {
                pid: record.pid,
                name: record.name.filter(|name| !name.is_empty()).unwrap_or_else(|| project.clone()),
                project,
                waiting_for: record.waiting_for.filter(|_| state == SessionState::Waiting),
                state,
                started_at: record.started_at.map(|ms| ms / 1000),
            }
        })
        .collect();
    out.sort_by_key(|session| (session.started_at, session.pid));
    out
}

/// Field `n` (1-based, as in proc(5)) of `/proc/<pid>/stat`. The command
/// name, field 2, is in parentheses and may hold spaces, so fields are
/// counted from after its closing one, which is field 3.
fn stat_field(proc_root: &Path, pid: u32, n: usize) -> Option<String> {
    let stat = fs::read_to_string(proc_root.join(pid.to_string()).join("stat")).ok()?;
    let (_, rest) = stat.rsplit_once(')')?;
    rest.split_whitespace().nth(n.checked_sub(3)?).map(str::to_string)
}

/// The process is still the one that wrote the record: field 22 of
/// `/proc/<pid>/stat` is its start time, which a reused pid won't share.
fn alive(proc_root: &Path, pid: u32, proc_start: Option<&str>) -> bool {
    match (stat_field(proc_root, pid, 22), proc_start) {
        (None, _) => false,
        (Some(_), None) => true,
        (Some(start), Some(expected)) => start == expected,
    }
}

/// The nearest ancestor of `pid` (itself included) that owns a window,
/// given each window's owning pid: the terminal the session runs in.
fn window_for(proc_root: &Path, pid: u32, windows: &[(u32, String)]) -> Option<String> {
    let mut current = pid;
    for _ in 0..64 {
        if let Some((_, address)) = windows.iter().find(|(owner, _)| *owner == current) {
            return Some(address.clone());
        }
        current = stat_field(proc_root, current, 4)?.parse().ok()?;
        if current <= 1 {
            return None;
        }
    }
    None
}

/// Bring the terminal a live session runs in to the front, on Hyprland.
pub fn focus(provider: &str, pid: u32) -> anyhow::Result<()> {
    use anyhow::{Context, bail};
    use std::process::Command;

    if !live(provider).iter().any(|session| session.pid == pid) {
        bail!("{pid} is not a live {provider} session");
    }
    let windows = hypr_windows().context("could not list Hyprland windows")?;
    let Some(address) = window_for(Path::new("/proc"), pid, &windows) else {
        bail!("no window found for session {pid}");
    };
    let status = Command::new("hyprctl")
        .args(["dispatch", "focuswindow", &format!("address:{address}")])
        .stdout(std::process::Stdio::null())
        .status()
        .context("could not run hyprctl")?;
    if !status.success() {
        bail!("hyprctl could not focus {address}");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn stat_line(pid: u32, start: &str) -> String {
        stat_with_parent(pid, 1, start)
    }

    fn stat_with_parent(pid: u32, ppid: u32, start: &str) -> String {
        let ppid = ppid.to_string();
        let mut fields = vec!["S", ppid.as_str()];
        fields.extend(std::iter::repeat_n("0", 17));
        fields.push(start);
        format!("{pid} (claude code) {}", fields.join(" "))
    }

    #[test]
    fn a_session_with_no_window_is_dropped_only_when_windows_are_known() {
        let (_root, _sessions, procfs) = setup();
        for (pid, ppid) in [(10, 5), (5, 1), (20, 6), (6, 1)] {
            let dir = procfs.join(pid.to_string());
            fs::create_dir_all(&dir).unwrap();
            fs::write(dir.join("stat"), stat_with_parent(pid, ppid, "7")).unwrap();
        }
        let session = |pid| Session {
            pid,
            name: String::new(),
            project: String::new(),
            state: SessionState::Idle,
            waiting_for: None,
            started_at: None,
        };
        let windows = vec![(5, "0x1".to_string())];
        let kept = with_window(vec![session(10), session(20)], &procfs, Some(&windows));
        assert_eq!(kept.iter().map(|s| s.pid).collect::<Vec<_>>(), vec![10]);
        assert_eq!(with_window(vec![session(10), session(20)], &procfs, None).len(), 2);
    }

    #[test]
    fn the_window_is_found_up_the_parent_chain() {
        let (_root, _sessions, procfs) = setup();
        for (pid, ppid) in [(300, 200), (200, 100), (100, 1)] {
            let dir = procfs.join(pid.to_string());
            fs::create_dir_all(&dir).unwrap();
            fs::write(dir.join("stat"), stat_with_parent(pid, ppid, "7")).unwrap();
        }
        let windows = vec![(100, "0xabc".to_string()), (999, "0xdef".to_string())];
        assert_eq!(window_for(&procfs, 300, &windows).as_deref(), Some("0xabc"));
        assert_eq!(window_for(&procfs, 300, &[(999, "0xdef".into())]), None);
    }

    fn setup() -> (tempfile::TempDir, std::path::PathBuf, std::path::PathBuf) {
        let root = tempfile::tempdir().unwrap();
        let sessions = root.path().join("sessions");
        let procfs = root.path().join("proc");
        fs::create_dir_all(&sessions).unwrap();
        fs::create_dir_all(&procfs).unwrap();
        (root, sessions, procfs)
    }

    fn process(procfs: &Path, pid: u32, start: &str) {
        let dir = procfs.join(pid.to_string());
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("stat"), stat_line(pid, start)).unwrap();
    }

    #[test]
    fn reads_live_sessions_in_start_order() {
        let (_root, sessions, procfs) = setup();
        process(&procfs, 20, "500");
        process(&procfs, 10, "400");
        fs::write(
            sessions.join("20.json"),
            r#"{"pid":20,"cwd":"/home/u/b","startedAt":2000000,"procStart":"500","name":"","status":"waiting","waitingFor":"input needed"}"#,
        )
        .unwrap();
        fs::write(
            sessions.join("10.json"),
            r#"{"pid":10,"cwd":"/home/u/.config/hypr","startedAt":1000000,"procStart":"400","name":"fix-bar","status":"busy"}"#,
        )
        .unwrap();

        let found = claude(&sessions, &procfs);
        assert_eq!(found.len(), 2);
        assert_eq!(found[0].name, "fix-bar");
        assert_eq!(found[0].project, "hypr");
        assert_eq!(found[0].state, SessionState::Busy);
        assert_eq!(found[0].started_at, Some(1000));
        assert_eq!(found[1].name, "b");
        assert_eq!(found[1].state, SessionState::Waiting);
        assert_eq!(found[1].waiting_for.as_deref(), Some("input needed"));
    }

    #[test]
    fn a_dead_or_reused_pid_is_dropped() {
        let (_root, sessions, procfs) = setup();
        process(&procfs, 30, "999");
        fs::write(sessions.join("30.json"), r#"{"pid":30,"procStart":"100","status":"busy"}"#).unwrap();
        fs::write(sessions.join("40.json"), r#"{"pid":40,"procStart":"100","status":"busy"}"#).unwrap();
        fs::write(sessions.join("40.abc.key"), "not json").unwrap();
        assert!(claude(&sessions, &procfs).is_empty());
    }

    #[test]
    fn an_unknown_status_reads_as_idle() {
        let (_root, sessions, procfs) = setup();
        process(&procfs, 50, "1");
        fs::write(sessions.join("50.json"), r#"{"pid":50,"procStart":"1","status":"something-new","waitingFor":"x"}"#).unwrap();
        let found = claude(&sessions, &procfs);
        assert_eq!(found[0].state, SessionState::Idle);
        assert_eq!(found[0].waiting_for, None);
    }
}
