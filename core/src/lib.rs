//! Data contract and provider registry for flare.
//!
//! `data.mode` in the config picks how a provider is read. `official`, the
//! default, follows Codenotch: the provider's own usage endpoint, called with
//! the credential its CLI or editor already stores, with what the CLI last
//! wrote to disk as the fallback. `local` never opens a network connection and
//! reads only what is on disk.
//!
//! Credentials are borrowed read-only and never written, printed or logged.

pub mod config;
pub mod history;
pub mod http;
pub mod jsonl;
pub mod paths;
pub mod providers;
pub mod sessions;
pub mod store;
#[cfg(test)]
mod testutil;
pub mod time;

use serde::{Deserialize, Serialize};

pub use config::Config;

/// A file was found but did not match the expected schema, which usually
/// means the provider changed its format.
pub fn err_parse(detail: impl std::fmt::Display) -> String {
    format!("parse error: {detail}")
}

/// Read from the provider's own usage endpoint.
pub const SOURCE_OFFICIAL: &str = "official";
/// Read from what a CLI wrote to disk.
pub const SOURCE_LOCAL: &str = "local";

/// How long a reading stands as current before it is shown as stale.
pub const CURRENT_FOR_SECS: i64 = 5 * 60;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Status {
    /// A reading taken just now, or recent enough to stand as current.
    Ok,
    /// The last good reading, kept because a fresh one could not be taken.
    Stale,
    /// No usable sign-in for this provider.
    NeedsAuth,
    /// Official mode would read this provider's own live session out of
    /// another program's private state and replay it — not done until the
    /// user has agreed to it once.
    NeedsConsent,
    /// Asked to slow down, with no earlier reading to show meanwhile.
    Backoff,
    /// A fresh reading failed and there is no earlier one to show.
    Error,
    /// Present, but nothing is metered or recorded yet.
    #[default]
    None,
    /// Not installed on this machine; the widget draws no cell for it.
    Absent,
}

/// What a single run needs to know besides the config.
pub struct Fetch {
    pub now: i64,
    /// Skip each provider's own pacing. A server's retry deadline still holds.
    pub force: bool,
}

/// One rate-limit window.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UsageWindow {
    /// Stable id: `session`, `weekly_all`, `primary`, `included`, ...
    pub id: String,
    /// The provider's own wording, in English; the widget translates it.
    pub label: String,
    /// A heading the window sits under on the card, e.g. Codex's "Spark".
    pub group: Option<String>,
    /// Fraction used, 0 to 1.
    pub used: f64,
    pub window_minutes: Option<i64>,
    /// Absolute reset time, unix seconds.
    pub resets_at: Option<i64>,
    pub resets_in_secs: Option<i64>,
    /// The reset time has passed since the reading was taken, so the provider
    /// is already in a fresh window; `used` then reads 0.
    pub reset_elapsed: bool,
}

impl UsageWindow {
    pub fn new(
        id: &str,
        label: impl Into<String>,
        used_percent: f64,
        window_minutes: Option<i64>,
        resets_at: Option<i64>,
    ) -> Self {
        Self {
            id: id.to_string(),
            label: label.into(),
            group: None,
            used: (used_percent / 100.0).clamp(0.0, 1.0),
            window_minutes,
            resets_at,
            resets_in_secs: None,
            reset_elapsed: false,
        }
    }

    pub fn grouped(mut self, group: &str) -> Self {
        self.group = Some(group.to_string());
        self
    }

    /// Bring the countdown up to `now`.
    pub fn settle(&mut self, now: i64) {
        self.reset_elapsed = self.resets_at.is_some_and(|at| at <= now);
        self.resets_in_secs = self.resets_at.map(|at| time::secs_until(at, now));
        if self.reset_elapsed {
            self.used = 0.0;
        }
    }

    /// Codenotch's rule: a window named only by its length says more as
    /// "5h limit" than as "primary". A free Codex plan runs a 30 day one.
    pub fn label_for_minutes(window_minutes: Option<i64>, slot: &str) -> String {
        match window_minutes {
            Some(minutes) if minutes > 0 && minutes < 60 => format!("{minutes}m limit"),
            Some(minutes) if minutes > 0 && minutes < 1440 => format!("{}h limit", minutes / 60),
            Some(minutes) if minutes > 0 => match (minutes as f64 / 1440.0).round() as i64 {
                7 => "Weekly limit".to_string(),
                30 => "Monthly limit".to_string(),
                days => format!("{days}d limit"),
            },
            _ if slot == "primary" => "Current session".to_string(),
            _ => "Longer window".to_string(),
        }
    }
}

/// A normalized usage snapshot for a single provider.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderUsage {
    /// "claude", "codex", "cursor" or "opencode".
    pub provider: String,
    pub status: Status,
    /// One line on why the status is what it is, for the hover card.
    pub note: Option<String>,
    /// `official` or `local`: where these windows came from.
    pub source: String,
    /// Whose readings these are. A label only, never used to authenticate.
    pub account: Option<String>,
    pub plan: Option<String>,
    /// Whether the provider enforces a rate-limit window at all. OpenCode runs
    /// on the user's own API keys and never does.
    pub metered: bool,
    pub windows: Vec<UsageWindow>,
    /// The window the ring draws, by id.
    pub headline: Option<String>,
    /// When the reading was taken: the request for a live reading, the line's
    /// own timestamp for one read off disk.
    pub fetched_at: Option<i64>,
    /// No network read for this provider before this time.
    pub backoff_until: Option<i64>,
    /// Tokens over the scanned window (`scan.window_days`).
    pub tokens_today: Option<u64>,
    pub cost_today_usd: Option<f64>,
    /// Locally derived costs are estimates and must never be shown as a bill.
    pub cost_is_estimated: bool,
    /// Category-prefixed detail for doctor, e.g. "parse error: ...".
    pub error: Option<String>,
    /// Sessions open right now. Read fresh on every run, never stored.
    #[serde(default, skip_deserializing)]
    pub sessions: Vec<sessions::Session>,
    /// How each window filled over time, `[unix seconds, fraction used]` per
    /// window id. Kept in its own file, not in the stored snapshot.
    #[serde(default, skip_deserializing)]
    pub history: history::History,
    /// Sessions seen over the last week, closed ones included.
    #[serde(default, skip_deserializing)]
    pub session_log: Vec<sessions::Logged>,
}

impl ProviderUsage {
    pub fn new(provider: &str, source: &str) -> Self {
        Self {
            provider: provider.to_string(),
            status: Status::None,
            note: None,
            source: source.to_string(),
            account: None,
            plan: None,
            metered: true,
            windows: Vec::new(),
            headline: None,
            fetched_at: None,
            backoff_until: None,
            tokens_today: None,
            cost_today_usd: None,
            cost_is_estimated: true,
            error: None,
            sessions: Vec::new(),
            history: history::History::new(),
            session_log: Vec::new(),
        }
    }

    pub fn absent(provider: &str) -> Self {
        let mut usage = Self::new(provider, SOURCE_LOCAL);
        usage.status = Status::Absent;
        usage
    }

    pub fn with_error(mut self, error: impl Into<String>) -> Self {
        self.error = Some(error.into());
        self
    }

    /// Bring every time-dependent field up to `now`: countdowns, a reading
    /// that has aged out of "current", a retry deadline that has passed, and a
    /// headline that must name a window this snapshot actually has.
    pub fn settle(&mut self, now: i64) {
        for window in &mut self.windows {
            window.settle(now);
        }
        if self.status == Status::Ok
            && self.fetched_at.is_some_and(|at| now - at > CURRENT_FOR_SECS)
        {
            self.status = Status::Stale;
        }
        if self.backoff_until.is_some_and(|until| until <= now) {
            self.backoff_until = None;
        }
        let headline_known = self
            .headline
            .as_ref()
            .is_some_and(|id| self.windows.iter().any(|w| &w.id == id));
        if !headline_known {
            self.headline = self.windows.first().map(|w| w.id.clone());
        }
    }
}

/// Reads one provider.
///
/// Every failure lands in the snapshot's `status`, `note` and `error`; an
/// `Err` means something went wrong before the provider could even look.
pub trait UsageProvider: Send + Sync {
    fn id(&self) -> &'static str;
    fn fetch(&self, ctx: &Fetch) -> anyhow::Result<ProviderUsage>;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn labels_follow_the_window_length() {
        assert_eq!(UsageWindow::label_for_minutes(Some(300), "primary"), "5h limit");
        assert_eq!(UsageWindow::label_for_minutes(Some(10_080), "primary"), "Weekly limit");
        assert_eq!(UsageWindow::label_for_minutes(Some(43_200), "primary"), "Monthly limit");
        assert_eq!(UsageWindow::label_for_minutes(Some(30), "primary"), "30m limit");
        assert_eq!(UsageWindow::label_for_minutes(None, "primary"), "Current session");
        assert_eq!(UsageWindow::label_for_minutes(None, "secondary"), "Longer window");
    }

    #[test]
    fn a_window_past_its_reset_reads_as_unused() {
        let mut window = UsageWindow::new("session", "Current session", 85.0, Some(300), Some(1_000));
        window.settle(2_000);
        assert!(window.reset_elapsed);
        assert_eq!(window.used, 0.0);
        assert_eq!(window.resets_in_secs, Some(0));
    }

    #[test]
    fn an_old_reading_turns_stale_and_the_headline_is_repaired() {
        let mut usage = ProviderUsage::new("claude", SOURCE_OFFICIAL);
        usage.status = Status::Ok;
        usage.fetched_at = Some(0);
        usage.headline = Some("gone".into());
        usage.windows = vec![UsageWindow::new("weekly_all", "Weekly (all models)", 10.0, None, None)];
        usage.settle(CURRENT_FOR_SECS + 1);
        assert_eq!(usage.status, Status::Stale);
        assert_eq!(usage.headline.as_deref(), Some("weekly_all"));
    }
}
