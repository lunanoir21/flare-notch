//! Reading JSONL logs that an agent may be appending to right now.
//!
//! These files are read best-effort and read-only: no locking, no exclusive
//! access, nothing that could block or interfere with the agent's own writes.
//!
//! The only tolerated damage is a partial final line, because that is what a
//! write racing with our read looks like. A parse failure on any earlier line
//! is a real schema problem and is reported, not swallowed.

use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;

use anyhow::{Context, Result, bail};
use serde_json::Value;

/// Call `visit` for every JSON object in a JSONL file, oldest line first.
///
/// Blank lines are skipped. The final line is skipped when it does not parse,
/// on the assumption that it is a truncated write in progress.
pub fn for_each<F>(path: &Path, mut visit: F) -> Result<()>
where
    F: FnMut(&Value),
{
    let file = File::open(path).with_context(|| format!("{}", path.display()))?;
    let reader = BufReader::new(file);

    // Hold each line back until we know another one follows it, so the last
    // line is never parsed under the strict rule.
    let mut pending: Option<(usize, String)> = None;

    for (index, line) in reader.lines().enumerate() {
        let line = line.with_context(|| format!("{}", path.display()))?;
        if let Some((prev_index, prev)) = pending.take() {
            if let Some(value) = parse_strict(path, prev_index, &prev)? {
                visit(&value);
            }
        }
        pending = Some((index, line));
    }

    if let Some((_, last)) = pending {
        if !last.trim().is_empty() {
            if let Ok(value) = serde_json::from_str::<Value>(&last) {
                visit(&value);
            }
        }
    }

    Ok(())
}

/// Parse a line that is known not to be the last one, so a failure is real.
fn parse_strict(path: &Path, index: usize, line: &str) -> Result<Option<Value>> {
    if line.trim().is_empty() {
        return Ok(None);
    }
    match serde_json::from_str::<Value>(line) {
        Ok(value) => Ok(Some(value)),
        Err(err) => bail!("{}:{}: {err}", path.display(), index + 1),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::fixture;

    fn count(relative: &str) -> Result<usize> {
        let mut seen = 0;
        for_each(&fixture(relative), |_| seen += 1)?;
        Ok(seen)
    }

    #[test]
    fn reads_every_line_of_a_well_formed_file() {
        assert_eq!(count("claude/sessions_ok/a.jsonl").unwrap(), 3);
    }

    #[test]
    fn skips_a_truncated_final_line() {
        // The agent was mid-write; the three complete records still count.
        assert_eq!(count("claude/sessions_truncated/a.jsonl").unwrap(), 3);
    }

    #[test]
    fn reports_damage_on_an_earlier_line() {
        let err = count("claude/sessions_malformed/a.jsonl").unwrap_err();
        let message = format!("{err:#}");
        assert!(message.contains(":2:"), "should name the line: {message}");
    }

    #[test]
    fn a_missing_file_is_an_error_not_a_panic() {
        assert!(count("claude/does_not_exist.jsonl").is_err());
    }
}
