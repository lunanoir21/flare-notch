//! What changed between two readings that is worth a desktop notification.
//!
//! Pure bookkeeping: `flare watch` feeds it sessions and usage and sends what
//! comes back. The first reading of anything is only a baseline, so starting
//! the watcher never replays what was already true.

use std::collections::HashMap;

use crate::config::Notify;
use crate::sessions::{Session, SessionState};
use crate::{ProviderUsage, Status};

/// A reset counts only if the window had been used at least this much.
const RESET_AFTER_USE: f64 = 0.05;

#[derive(Debug, Clone, PartialEq)]
pub enum Event {
    /// A session stopped and is waiting on the user.
    Waiting { provider: String, pid: u32, name: String, waiting_for: Option<String> },
    /// A window reached the configured share.
    Limit { provider: String, window: String, used: f64 },
    /// A window that had been used started over.
    Reset { provider: String, window: String },
}

#[derive(Debug, Clone, Copy)]
struct Mark {
    used: f64,
    resets_at: Option<i64>,
    reset_elapsed: bool,
    /// The window period (by its reset time) a limit alert was already sent for.
    alerted_for: Option<Option<i64>>,
}

#[derive(Debug, Default)]
pub struct Tracker {
    sessions: HashMap<(String, u32), SessionState>,
    seen_sessions: HashMap<String, bool>,
    windows: HashMap<(String, String), Mark>,
}

impl Tracker {
    pub fn sessions(&mut self, provider: &str, now: &[Session], rules: &Notify) -> Vec<Event> {
        let first = !self.seen_sessions.contains_key(provider);
        self.seen_sessions.insert(provider.to_string(), true);
        let mut events = Vec::new();
        for session in now {
            let key = (provider.to_string(), session.pid);
            let before = self.sessions.insert(key, session.state);
            let became_waiting = session.state == SessionState::Waiting && before != Some(SessionState::Waiting);
            if became_waiting && !first && rules.waiting {
                events.push(Event::Waiting {
                    provider: provider.to_string(),
                    pid: session.pid,
                    name: session.name.clone(),
                    waiting_for: session.waiting_for.clone(),
                });
            }
        }
        self.sessions
            .retain(|(p, pid), _| p != provider || now.iter().any(|s| s.pid == *pid));
        events
    }

    pub fn usage(&mut self, usage: &ProviderUsage, rules: &Notify) -> Vec<Event> {
        let mut events = Vec::new();
        if !usage.metered || !matches!(usage.status, Status::Ok | Status::Stale) {
            return events;
        }
        let threshold = f64::from(rules.limit_at) / 100.0;
        for window in &usage.windows {
            let key = (usage.provider.clone(), window.id.clone());
            let Some(before) = self.windows.get(&key).copied() else {
                let alerted_for = (window.used >= threshold).then_some(window.resets_at);
                self.windows.insert(
                    key,
                    Mark { used: window.used, resets_at: window.resets_at, reset_elapsed: window.reset_elapsed, alerted_for },
                );
                continue;
            };
            let moved_on = match (before.resets_at, window.resets_at) {
                (Some(old), Some(new)) => new > old + 600,
                _ => false,
            };
            let started_over = moved_on || (window.reset_elapsed && !before.reset_elapsed);
            let mut alerted_for = before.alerted_for;
            if started_over {
                alerted_for = None;
                if rules.reset && before.used >= RESET_AFTER_USE {
                    events.push(Event::Reset { provider: usage.provider.clone(), window: window.label.clone() });
                }
            }
            let period = window.resets_at;
            if window.used >= threshold && alerted_for != Some(period) {
                if rules.limit {
                    events.push(Event::Limit {
                        provider: usage.provider.clone(),
                        window: window.label.clone(),
                        used: window.used,
                    });
                }
                alerted_for = Some(period);
            }
            self.windows.insert(
                key,
                Mark { used: window.used, resets_at: window.resets_at, reset_elapsed: window.reset_elapsed, alerted_for },
            );
        }
        events
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{SOURCE_OFFICIAL, UsageWindow};

    fn rules() -> Notify {
        Notify { waiting: true, limit: true, limit_at: 90, reset: true }
    }

    fn session(pid: u32, state: SessionState) -> Session {
        Session { pid, name: format!("s{pid}"), project: String::new(), state, waiting_for: None, started_at: None }
    }

    fn reading(used: f64, resets_at: i64) -> ProviderUsage {
        let mut usage = ProviderUsage::new("claude", SOURCE_OFFICIAL);
        usage.status = Status::Ok;
        usage.windows = vec![UsageWindow::new("session", "Current session", used * 100.0, Some(300), Some(resets_at))];
        usage
    }

    #[test]
    fn the_first_look_is_only_a_baseline() {
        let mut tracker = Tracker::default();
        assert!(tracker.sessions("claude", &[session(1, SessionState::Waiting)], &rules()).is_empty());
        assert!(tracker.usage(&reading(0.95, 1000), &rules()).is_empty());
    }

    #[test]
    fn a_session_that_starts_waiting_is_announced_once() {
        let mut tracker = Tracker::default();
        tracker.sessions("claude", &[session(1, SessionState::Busy)], &rules());
        let events = tracker.sessions("claude", &[session(1, SessionState::Waiting)], &rules());
        assert!(matches!(events.as_slice(), [Event::Waiting { pid: 1, .. }]));
        assert!(tracker.sessions("claude", &[session(1, SessionState::Waiting)], &rules()).is_empty());
        // A new session that shows up already waiting counts too.
        let events = tracker.sessions("claude", &[session(1, SessionState::Waiting), session(2, SessionState::Waiting)], &rules());
        assert!(matches!(events.as_slice(), [Event::Waiting { pid: 2, .. }]));
    }

    #[test]
    fn a_limit_alert_fires_once_per_window_period() {
        let mut tracker = Tracker::default();
        tracker.usage(&reading(0.50, 1000), &rules());
        assert!(matches!(tracker.usage(&reading(0.91, 1000), &rules()).as_slice(), [Event::Limit { .. }]));
        assert!(tracker.usage(&reading(0.97, 1000), &rules()).is_empty());
    }

    #[test]
    fn a_used_window_that_starts_over_is_announced_and_rearms_the_alert() {
        let mut tracker = Tracker::default();
        tracker.usage(&reading(0.50, 1000), &rules());
        tracker.usage(&reading(0.92, 1000), &rules());
        let events = tracker.usage(&reading(0.0, 1000 + 18_000), &rules());
        assert!(matches!(events.as_slice(), [Event::Reset { .. }]));
        assert!(matches!(tracker.usage(&reading(0.93, 1000 + 18_000), &rules()).as_slice(), [Event::Limit { .. }]));
    }

    #[test]
    fn an_unused_window_starting_over_is_not_news() {
        let mut tracker = Tracker::default();
        tracker.usage(&reading(0.0, 1000), &rules());
        assert!(tracker.usage(&reading(0.0, 1000 + 18_000), &rules()).is_empty());
    }

    #[test]
    fn switched_off_rules_stay_quiet() {
        let off = Notify { waiting: false, limit: false, limit_at: 90, reset: false };
        let mut tracker = Tracker::default();
        tracker.sessions("claude", &[session(1, SessionState::Busy)], &off);
        assert!(tracker.sessions("claude", &[session(1, SessionState::Waiting)], &off).is_empty());
        tracker.usage(&reading(0.5, 1000), &off);
        assert!(tracker.usage(&reading(0.95, 1000), &off).is_empty());
    }
}
