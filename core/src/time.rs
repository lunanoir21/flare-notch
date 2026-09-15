//! Timestamp helpers shared by the log parsers.

use chrono::DateTime;

/// Parse an RFC 3339 timestamp into unix seconds.
///
/// Session logs write UTC with a trailing `Z`, but the offset form is equally
/// valid RFC 3339, so both are accepted rather than assumed.
pub fn rfc3339_to_unix(text: &str) -> Option<i64> {
    DateTime::parse_from_rfc3339(text)
        .ok()
        .map(|dt| dt.timestamp())
}

/// Seconds until `resets_at`, clamped at zero.
///
/// A window whose reset time has already passed reads as 0 rather than a
/// negative countdown, which would render as a nonsense value.
pub fn secs_until(resets_at: i64, now: i64) -> i64 {
    (resets_at - now).max(0)
}
