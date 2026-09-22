//! How each limit filled over time, kept locally so the hover card can draw it.
//!
//! One file per provider under $XDG_STATE_HOME/flare, a list of
//! `[unix seconds, fraction used]` per window id. Only fresh readings are
//! recorded, a repeat of the same value no more than every few minutes, and
//! each list is trimmed to the window's own length.

use std::collections::BTreeMap;
use std::path::PathBuf;

use crate::{ProviderUsage, Status, paths};

pub type Points = Vec<(i64, f64)>;
pub type History = BTreeMap<String, Points>;

/// A repeat of the last value is kept only this often.
const SAME_VALUE_EVERY_SECS: i64 = 5 * 60;
/// For a window with no known length.
const DEFAULT_SPAN_SECS: i64 = 24 * 3600;
const MAX_POINTS: usize = 400;

/// Add this reading to the provider's history and return the history, trimmed.
pub fn record(usage: &ProviderUsage, now: i64) -> History {
    let Some(path) = file(&usage.provider) else {
        return History::new();
    };
    let mut history: History = std::fs::read_to_string(&path)
        .ok()
        .and_then(|text| serde_json::from_str(&text).ok())
        .unwrap_or_default();
    if add(&mut history, usage, now) {
        if let Ok(text) = serde_json::to_string(&history) {
            let _ = crate::store::write_private(&path, &text);
        }
    }
    history
}

/// Returns whether anything changed.
fn add(history: &mut History, usage: &ProviderUsage, now: i64) -> bool {
    let mut changed = false;
    let fresh = usage.status == Status::Ok && usage.metered;
    if let (true, Some(at)) = (fresh, usage.fetched_at) {
        for window in &usage.windows {
            let points = history.entry(window.id.clone()).or_default();
            let keep = match points.last() {
                None => true,
                Some(&(last_at, last_used)) => {
                    at > last_at && ((window.used - last_used).abs() > 0.001 || at - last_at >= SAME_VALUE_EVERY_SECS)
                }
            };
            if keep {
                points.push((at, window.used));
                changed = true;
            }
        }
    }
    for (id, points) in history.iter_mut() {
        let span = usage
            .windows
            .iter()
            .find(|w| &w.id == id)
            .and_then(|w| w.window_minutes)
            .filter(|&minutes| minutes > 0)
            .map_or(DEFAULT_SPAN_SECS, |minutes| minutes * 60);
        let before = points.len();
        points.retain(|&(at, _)| at >= now - span && at <= now + 60);
        if points.len() > MAX_POINTS {
            points.drain(..points.len() - MAX_POINTS);
        }
        changed |= points.len() != before;
    }
    let before = history.len();
    history.retain(|_, points| !points.is_empty());
    changed | (history.len() != before)
}

fn file(provider: &str) -> Option<PathBuf> {
    paths::flare_state()
        .ok()
        .map(|dir| dir.join(format!("history-{provider}.json")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{SOURCE_OFFICIAL, UsageWindow};

    fn usage(at: i64, used: f64) -> ProviderUsage {
        let mut usage = ProviderUsage::new("claude", SOURCE_OFFICIAL);
        usage.status = Status::Ok;
        usage.fetched_at = Some(at);
        usage.windows = vec![UsageWindow::new("session", "Current session", used * 100.0, Some(300), None)];
        usage
    }

    #[test]
    fn a_new_value_is_kept_and_a_repeat_only_every_few_minutes() {
        let mut history = History::new();
        assert!(add(&mut history, &usage(1000, 0.10), 1000));
        assert!(!add(&mut history, &usage(1060, 0.10), 1060));
        assert!(add(&mut history, &usage(1120, 0.12), 1120));
        assert!(add(&mut history, &usage(1120 + SAME_VALUE_EVERY_SECS, 0.12), 1120 + SAME_VALUE_EVERY_SECS));
        assert_eq!(history["session"].len(), 3);
    }

    #[test]
    fn points_older_than_the_window_are_dropped() {
        let mut history = History::new();
        add(&mut history, &usage(1000, 0.10), 1000);
        // A 5 hour window: an hour-old point stays, a six-hour-old one goes.
        add(&mut history, &usage(1000 + 3600, 0.20), 1000 + 3600);
        add(&mut history, &usage(1000 + 6 * 3600, 0.30), 1000 + 6 * 3600);
        let at: Vec<i64> = history["session"].iter().map(|p| p.0).collect();
        assert_eq!(at, vec![1000 + 3600, 1000 + 6 * 3600]);
    }

    #[test]
    fn a_stale_or_failed_reading_is_not_recorded() {
        let mut history = History::new();
        let mut stale = usage(1000, 0.5);
        stale.status = Status::Stale;
        assert!(!add(&mut history, &stale, 1000));
        assert!(history.is_empty());
    }
}
