//! Filesystem locations, resolved through XDG environment variables.
//!
//! Provider directories that predate XDG (Claude Code, Codex) keep their
//! documented default but honor the environment variable each CLI itself
//! supports, so flare follows a relocated install instead of hardcoding a
//! path under $HOME.

use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};

/// $XDG_CONFIG_HOME, or ~/.config.
pub fn config_dir() -> Result<PathBuf> {
    dirs::config_dir().context("cannot resolve a config directory for this user")
}

/// $XDG_DATA_HOME, or ~/.local/share.
pub fn data_dir() -> Result<PathBuf> {
    dirs::data_dir().context("cannot resolve a data directory for this user")
}

/// $XDG_STATE_HOME, or ~/.local/state.
pub fn state_dir() -> Result<PathBuf> {
    dirs::state_dir().context("cannot resolve a state directory for this user")
}

pub fn home_dir() -> Result<PathBuf> {
    dirs::home_dir().context("cannot resolve a home directory for this user")
}

/// Claude Code's own directory: $CLAUDE_CONFIG_DIR, or ~/.claude.
pub fn claude_home() -> Result<PathBuf> {
    match std::env::var_os("CLAUDE_CONFIG_DIR") {
        Some(dir) if !dir.is_empty() => Ok(PathBuf::from(dir)),
        _ => Ok(home_dir()?.join(".claude")),
    }
}

/// Claude Code's account file, which sits beside the directory rather than
/// inside it.
pub fn claude_account_file() -> Result<PathBuf> {
    Ok(home_dir()?.join(".claude.json"))
}

/// Codex's own directory: $CODEX_HOME, or ~/.codex.
pub fn codex_home() -> Result<PathBuf> {
    match std::env::var_os("CODEX_HOME") {
        Some(dir) if !dir.is_empty() => Ok(PathBuf::from(dir)),
        _ => Ok(home_dir()?.join(".codex")),
    }
}

/// OpenCode's data directory.
pub fn opencode_data() -> Result<PathBuf> {
    Ok(data_dir()?.join("opencode"))
}

/// The Cursor editor's global state database, where it keeps its sign-in.
pub fn cursor_state_db() -> Result<PathBuf> {
    Ok(config_dir()?
        .join("Cursor")
        .join("User")
        .join("globalStorage")
        .join("state.vscdb"))
}

/// Where flare's own state lives, including the status line capture written
/// by hooks/claude-statusline-capture.sh.
pub fn flare_state() -> Result<PathBuf> {
    Ok(state_dir()?.join("flare"))
}

/// Unix mtime of a path, for `ProviderUsage::data_as_of_secs`.
///
/// This is the freshness signal that matters: the data only changes when the
/// agent itself writes, not when flare runs.
pub fn mtime_secs(path: &Path) -> Option<i64> {
    let modified = std::fs::metadata(path).ok()?.modified().ok()?;
    let since_epoch = modified.duration_since(UNIX_EPOCH).ok()?;
    i64::try_from(since_epoch.as_secs()).ok()
}

/// Every file under `dir` with the given extension, searched recursively.
///
/// Unreadable directories are skipped rather than failing the scan: a log
/// tree is best-effort input, and one bad subdirectory should not blank out
/// the whole provider.
pub fn collect_files(dir: &Path, extension: &str) -> Vec<PathBuf> {
    let mut found = Vec::new();
    collect_into(dir, extension, &mut found);
    found
}

fn collect_into(dir: &Path, extension: &str, found: &mut Vec<PathBuf>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        match entry.file_type() {
            Ok(file_type) if file_type.is_dir() => collect_into(&path, extension, found),
            Ok(file_type)
                if file_type.is_file() && path.extension().is_some_and(|ext| ext == extension) =>
            {
                found.push(path);
            }
            _ => {}
        }
    }
}

/// Current unix timestamp in seconds.
pub fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .ok()
        .and_then(|d| i64::try_from(d.as_secs()).ok())
        .unwrap_or_default()
}
