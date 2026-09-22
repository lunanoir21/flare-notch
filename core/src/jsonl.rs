//! Reading JSONL logs that an agent may be appending to right now.
//!
//! These files are read best-effort and read-only: no locking, no exclusive
//! access, nothing that could block or interfere with the agent's own writes.
//!
//! The only tolerated damage is a partial final line, because that is what a
//! write racing with our read looks like. A parse failure on any earlier line
//! is a real schema problem and is reported, not swallowed.
//!
//! A single line and the file as a whole are both bounded: an agent's own log
//! is well-behaved, but nothing here should trust that completely. A line (or
//! a file) that blows past the ceiling is reported the same way a malformed
//! line already is, not silently truncated.

use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;

use anyhow::{Context, Result, bail};
use serde_json::Value;

/// A line longer than this is skipped without being held in memory. The
/// records flare reads are small; the lines this long are tool output such as
/// a screenshot, and one of them must not cost the rest of the file.
const MAX_LINE_BYTES: usize = 64 * 1024;
/// Total bytes read from one file before the scan gives up on it. A long
/// Claude Code session's log passes 64 MB.
const MAX_TOTAL_BYTES: u64 = 256 * 1024 * 1024;

/// Call `visit` for every JSON object in a JSONL file, oldest line first.
///
/// Blank lines are skipped. The final line is skipped when it does not parse,
/// on the assumption that it is a truncated write in progress.
pub fn for_each<F>(path: &Path, mut visit: F) -> Result<()>
where
    F: FnMut(&Value),
{
    let file = File::open(path).with_context(|| format!("{}", path.display()))?;
    let mut reader = BufReader::new(file);

    // Hold each line back until we know another one follows it, so the last
    // line is never parsed under the strict rule.
    let mut pending: Option<(usize, Vec<u8>)> = None;
    let mut total: u64 = 0;

    for index in 0.. {
        let Some(line) = read_bounded_line(&mut reader, path, &mut total)? else {
            break;
        };
        if let Some((prev_index, prev)) = pending.take() {
            if let Some(value) = parse_strict(path, prev_index, &prev)? {
                visit(&value);
            }
        }
        pending = Some((index, line));
    }

    if let Some((_, last)) = pending {
        if !last.iter().all(|b| b.is_ascii_whitespace()) {
            if let Ok(value) = serde_json::from_slice::<Value>(&last) {
                visit(&value);
            }
        }
    }

    Ok(())
}

/// Reads one line (without its trailing newline), bounded by
/// `MAX_TOTAL_BYTES` for the whole file. A line past `MAX_LINE_BYTES` is
/// read through and dropped, coming back empty, which the caller skips like
/// a blank line. `Ok(None)` at a clean EOF with nothing pending; the final
/// unterminated fragment before EOF still comes back as a line, matching
/// `BufRead::lines()`.
fn read_bounded_line(reader: &mut BufReader<File>, path: &Path, total: &mut u64) -> Result<Option<Vec<u8>>> {
    let mut out = Vec::new();
    let mut skipping = false;
    loop {
        let available = reader.fill_buf().with_context(|| format!("{}", path.display()))?;
        if available.is_empty() {
            return Ok(if out.is_empty() && !skipping { None } else { Some(out) });
        }
        let newline = available.iter().position(|&b| b == b'\n');
        let take = newline.unwrap_or(available.len());
        if skipping || out.len() + take > MAX_LINE_BYTES {
            skipping = true;
            out = Vec::new();
        } else {
            out.extend_from_slice(&available[..take]);
        }
        let consumed = newline.map_or(take, |pos| pos + 1);
        *total += consumed as u64;
        reader.consume(consumed);
        check_total(path, *total)?;
        if newline.is_some() {
            return Ok(Some(out));
        }
    }
}

fn check_total(path: &Path, total: u64) -> Result<()> {
    if total > MAX_TOTAL_BYTES {
        bail!("{}: more than {MAX_TOTAL_BYTES} bytes, giving up on it", path.display());
    }
    Ok(())
}

/// Parse a line that is known not to be the last one, so a failure is real.
fn parse_strict(path: &Path, index: usize, line: &[u8]) -> Result<Option<Value>> {
    if line.iter().all(|b| b.is_ascii_whitespace()) {
        return Ok(None);
    }
    match serde_json::from_slice::<Value>(line) {
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

    #[test]
    fn a_line_past_the_byte_cap_is_skipped_and_the_rest_still_read() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("huge.jsonl");
        let huge = format!("{{\"pad\":\"{}\"}}", "a".repeat(MAX_LINE_BYTES * 4));
        std::fs::write(&path, format!("{{\"n\":1}}\n{huge}\n{{\"n\":2}}\n{{\"n\":3}}\n")).unwrap();
        let mut seen = Vec::new();
        for_each(&path, |value| seen.push(value["n"].as_i64().unwrap())).unwrap();
        assert_eq!(seen, vec![1, 2, 3]);
    }

    #[test]
    fn a_huge_unterminated_last_line_is_dropped_quietly() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("huge.jsonl");
        // No newline at all: a pathological single "line" many times the cap.
        std::fs::write(&path, "a".repeat(MAX_LINE_BYTES * 4)).unwrap();
        let mut seen = 0;
        for_each(&path, |_| seen += 1).unwrap();
        assert_eq!(seen, 0);
    }

    #[test]
    fn a_file_past_the_total_byte_cap_is_reported() {
        // Lines near (but under) the per-line cap, so the total cap trips
        // first without needing millions of lines to get there.
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("long.jsonl");
        let padding = " ".repeat(MAX_LINE_BYTES - 32);
        let line = format!("{{\"n\":1,\"pad\":\"{padding}\"}}\n");
        let repeats = (MAX_TOTAL_BYTES as usize / line.len()) + 4;
        std::fs::write(&path, line.repeat(repeats)).unwrap();
        let mut seen = 0;
        let err = for_each(&path, |_| seen += 1).unwrap_err();
        assert!(format!("{err:#}").contains("giving up"), "{err:#}");
        // The cap tripped partway through, not on the very first line.
        assert!(seen > 0, "should have made progress before the cap tripped");
    }
}
