//! What flare remembers between runs, one file per provider under
//! $XDG_STATE_HOME/flare.
//!
//! The widget starts a new `flare` process for every refresh, so the last good
//! reading, a server's retry deadline and the token renewal bookkeeping have
//! to outlive the process. No token is ever written here.

use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{ProviderUsage, paths};

#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Saved {
    /// The last snapshot this provider produced.
    pub usage: Option<ProviderUsage>,
    /// When the network was last asked, successful or not.
    pub last_attempt: Option<i64>,
    pub backoff_until: Option<i64>,
    pub consecutive_429: u32,
    /// The token expiry (ms) a renewal was last attempted for: one try per token.
    pub renew_attempted_for: Option<i64>,
    pub renew_last_attempt: Option<i64>,
}

impl Saved {
    pub fn load(provider: &str) -> Self {
        file(provider)
            .and_then(|path| std::fs::read_to_string(path).ok())
            .and_then(|text| serde_json::from_str(&text).ok())
            .unwrap_or_default()
    }

    /// Best effort: a state directory that cannot be written costs only the
    /// pacing, never a reading.
    pub fn save(&self, provider: &str) {
        let Some(path) = file(provider) else { return };
        if let Ok(text) = serde_json::to_string_pretty(self) {
            let _ = write_private(&path, &text);
        }
    }

    /// Whether this provider's own pace allows another network read.
    pub fn due(&self, now: i64, interval_secs: i64, force: bool) -> bool {
        force
            || self
                .last_attempt
                .is_none_or(|at| at > now || now - at >= interval_secs)
    }

    pub fn backing_off(&self, now: i64) -> Option<i64> {
        self.backoff_until.filter(|&until| until > now)
    }
}

fn file(provider: &str) -> Option<PathBuf> {
    paths::flare_state()
        .ok()
        .map(|dir| dir.join(format!("{provider}.json")))
}

fn write_private(path: &Path, text: &str) -> std::io::Result<()> {
    let dir = path
        .parent()
        .ok_or_else(|| std::io::Error::other("state file has no parent directory"))?;
    std::fs::create_dir_all(dir)?;
    let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("state");
    let tmp = dir.join(format!(".{name}.{}", std::process::id()));
    let mut out = std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&tmp)?;
    out.write_all(text.as_bytes())?;
    std::fs::rename(&tmp, path)
}

/// How long to wait after a 429: a minute, doubling per 429 in a row, capped
/// at 15 minutes. The server's Retry-After raises it, even past the cap.
pub fn backoff_secs(consecutive: u32, retry_after: u64) -> u64 {
    const BASE: u64 = 60;
    const CAP: u64 = 900;
    BASE.saturating_mul(1 << consecutive.min(4))
        .clamp(BASE, CAP)
        .max(retry_after)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backoff_doubles_to_a_cap_that_retry_after_may_exceed() {
        assert_eq!(backoff_secs(0, 0), 60);
        assert_eq!(backoff_secs(1, 0), 120);
        assert_eq!(backoff_secs(9, 0), 900);
        assert_eq!(backoff_secs(0, 3600), 3600);
    }

    #[test]
    fn pacing_holds_until_the_interval_passes_or_a_refresh_is_forced() {
        let saved = Saved { last_attempt: Some(100), ..Saved::default() };
        assert!(!saved.due(130, 60, false));
        assert!(saved.due(130, 60, true));
        assert!(saved.due(160, 60, false));
        // A clock that moved backwards must not stall reads forever.
        assert!(saved.due(50, 60, false));
    }
}
