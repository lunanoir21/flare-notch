//! Helpers shared by the unit tests.
//!
//! Fixtures are small hand-written files under core/tests/fixtures with every
//! account identifier redacted. No test reads the running user's real
//! ~/.claude, ~/.codex or OpenCode data.

use std::path::{Path, PathBuf};

/// Resolve a path under core/tests/fixtures.
pub fn fixture(relative: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("fixtures")
        .join(relative)
}

/// A cutoff that admits every fixture entry.
///
/// Fixtures carry fixed timestamps, so a cutoff derived from the clock would
/// make these tests start failing on a future date.
pub const NO_CUTOFF: i64 = 0;
