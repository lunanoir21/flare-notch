//! $XDG_CONFIG_HOME/flare/config.toml.
//!
//! Every field is optional. A missing file, an unreadable file and a
//! malformed file all fall back to defaults, because a hand-edited typo
//! should never stop the widget from rendering.
//!
//! The file is edited by hand or with `flare config set`, which validates the
//! value and keeps the file's comments. The settings page runs that same
//! command, so there is one writer and one set of rules.
//!
//! Nothing secret belongs here.

use std::ops::RangeInclusive;
use std::path::{Path, PathBuf};

use anyhow::{Context, bail, ensure};
use serde::{Deserialize, Serialize};
use toml_edit::{Array, DocumentMut, Item, Value};

use crate::paths;
use crate::providers::IDS;

/// Where usage numbers come from.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum DataMode {
    /// The providers' own usage endpoints, called with the sign-in each CLI
    /// or editor already keeps, falling back to what is on disk. Codenotch's way.
    #[default]
    Official,
    /// Never touch the network.
    Local,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Style {
    /// Codenotch's notch: every provider as a ring.
    #[default]
    Classic,
    /// One provider at a time, tinted with its colour.
    Aura,
    /// A thin strip on the top or bottom edge that opens with a tap.
    Compact,
}

/// The edge classic and aura sit on.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Edge {
    #[default]
    Left,
    Right,
}

/// How the body meets the screen edge, as in Quay.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Mount {
    /// Welded to the edge with inverse rounded corners: Codenotch's notch.
    #[default]
    Bridge,
    /// A rounded panel held off the edge by `notch.gap`.
    Floating,
    /// A strip along the whole edge that flares into the screen at both ends.
    Flush,
}

/// When the widget is on screen.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Reveal {
    #[default]
    Always,
    /// Tucked past the edge until the pointer reaches it.
    Hover,
    /// Tucked past the edge until the `toggleVisible` IPC call, e.g. from a keybind.
    Shortcut,
}

/// The edge the compact strip sits on.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CompactEdge {
    #[default]
    Top,
    Bottom,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum OpenOn {
    #[default]
    Click,
    Hover,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Data {
    pub mode: DataMode,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Notch {
    pub style: Style,
    pub mount: Mount,
    /// Floating only: pixels between the panel and the screen edge.
    pub gap: u32,
    pub reveal: Reveal,
    /// Hover only: how long the pointer rests on the edge before it slides in.
    pub reveal_delay_ms: u32,
    /// Hover only: how long after the pointer leaves before it slides away.
    pub hide_delay_ms: u32,
    pub edge: Edge,
    /// Pixels along the edge away from centre; positive moves down.
    pub offset: i32,
    pub scale: f64,
    /// Output name such as "eDP-1". Empty shows it on every screen.
    pub screen: String,
}

impl Default for Notch {
    fn default() -> Self {
        Self {
            style: Style::Classic,
            mount: Mount::Bridge,
            gap: 8,
            reveal: Reveal::Always,
            reveal_delay_ms: 80,
            hide_delay_ms: 400,
            edge: Edge::Left,
            offset: 0,
            scale: 1.0,
            screen: String::new(),
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Compact {
    pub edge: CompactEdge,
    /// Pixels along the edge away from centre; positive moves right.
    pub offset: i32,
    pub open_on: OpenOn,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Providers {
    pub claude: bool,
    pub codex: bool,
    pub cursor: bool,
    pub opencode: bool,
    /// Drawing order, and the order aura steps through.
    pub order: Vec<String>,
}

impl Default for Providers {
    fn default() -> Self {
        Self {
            claude: true,
            codex: true,
            cursor: true,
            opencode: true,
            order: ["claude", "codex", "opencode", "cursor"].map(String::from).to_vec(),
        }
    }
}

/// The colour aura takes on for each provider, as `#RRGGBB`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Aura {
    pub claude: String,
    pub codex: String,
    pub cursor: String,
    pub opencode: String,
}

impl Default for Aura {
    fn default() -> Self {
        Self {
            claude: "#D97757".into(),
            codex: "#6E7BFF".into(),
            cursor: "#3DD6C6".into(),
            opencode: "#C9CED6".into(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Poll {
    pub interval_secs: u64,
}

impl Default for Poll {
    fn default() -> Self {
        Self { interval_secs: 30 }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Scan {
    /// Days of local logs counted toward the token totals.
    pub window_days: u32,
}

impl Default for Scan {
    fn default() -> Self {
        Self { window_days: 1 }
    }
}

/// Path override for a program. Empty means "look it up on PATH".
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Binary {
    pub binary_path: Option<String>,
}

impl Binary {
    pub fn command<'a>(&'a self, fallback: &'a str) -> &'a str {
        match self.binary_path.as_deref() {
            Some(path) if !path.trim().is_empty() => path,
            _ => fallback,
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    pub data: Data,
    pub notch: Notch,
    pub compact: Compact,
    pub providers: Providers,
    pub aura: Aura,
    pub poll: Poll,
    pub scan: Scan,
    pub opencode: Binary,
    pub codex: Binary,
    /// The flare binary itself, for a compositor that starts Quickshell
    /// without the login shell's PATH.
    pub flare: Binary,
}

pub const SCALE_RANGE: RangeInclusive<f64> = 0.5..=2.0;
pub const MIN_POLL_SECS: u64 = 5;
pub const MAX_GAP: u32 = 64;
pub const MAX_DELAY_MS: u32 = 5000;

/// Every key `flare config set` accepts.
pub const KEYS: &[&str] = &[
    "data.mode",
    "notch.style",
    "notch.mount",
    "notch.gap",
    "notch.reveal",
    "notch.reveal_delay_ms",
    "notch.hide_delay_ms",
    "notch.edge",
    "notch.offset",
    "notch.scale",
    "notch.screen",
    "compact.edge",
    "compact.offset",
    "compact.open_on",
    "providers.claude",
    "providers.codex",
    "providers.cursor",
    "providers.opencode",
    "providers.order",
    "aura.claude",
    "aura.codex",
    "aura.cursor",
    "aura.opencode",
    "poll.interval_secs",
    "scan.window_days",
    "opencode.binary_path",
    "codex.binary_path",
    "flare.binary_path",
];

/// What `flare config init` writes: every default, explained.
pub const TEMPLATE: &str = r##"# flare configuration.
#
# Every key is optional; delete a line to get its default back.
# Edit this file directly, or from a terminal:
#   flare config set notch.style aura
# The widget picks up a change within a second of the file being saved.

[data]
# Where usage numbers come from.
#   official  each provider's own usage endpoint, called with the sign-in its
#             CLI or editor already keeps, as Codenotch does
#   local     never touch the network; read only what the CLIs wrote to disk
mode = "official"

[notch]
# classic  Codenotch's notch, every provider as a ring
# aura     one provider at a time, tinted with its colour
# compact  a thin strip on the top or bottom edge, opened with a tap
style = "classic"
# How it meets the screen edge, in every style:
#   bridge    welded to the edge with inverse rounded corners (Codenotch's notch)
#   floating  a rounded panel held off the edge by `gap`
#   flush     a strip along the whole edge, flaring into the screen at both ends
mount = "bridge"
# Floating only: pixels between the panel and the screen edge, 0 to 64.
gap = 8
# When it is on screen:
#   always    always there
#   hover     tucked past the edge until the pointer reaches it
#   shortcut  tucked away until `qs ipc call flare toggleVisible` (bind it to a key)
reveal = "always"
# Hover only: how long the pointer rests on the edge before it slides in, and
# how long after the pointer leaves before it slides away. 0 to 5000.
reveal_delay_ms = 80
hide_delay_ms = 400
# Edge for classic and aura: left or right.
edge = "left"
# Pixels to slide along the edge from the centre; positive moves it down.
offset = 0
# Size multiplier, from 0.5 to 2.0.
scale = 1.0
# Output to show it on, as `hyprctl monitors` names it. Empty: every screen.
screen = ""

[compact]
# top or bottom.
edge = "top"
# Pixels to slide along the edge from the centre; positive moves it right.
offset = 0
# click: one tap opens it and another closes it · hover: open while pointed at
open_on = "click"

[providers]
claude = true
codex = true
cursor = true
opencode = true
# The order cells are drawn in, and the order aura steps through.
order = ["claude", "codex", "opencode", "cursor"]

[aura]
# The colour aura takes on for each provider.
claude = "#D97757"
codex = "#6E7BFF"
cursor = "#3DD6C6"
opencode = "#C9CED6"

[poll]
# Seconds between widget refreshes, at least 5. Network reads keep their own
# slower pace: Claude every minute, Codex and Cursor every five.
interval_secs = 30

[scan]
# Days of local logs counted toward the token totals.
window_days = 1

# Where to find a program that is not on PATH.
[opencode]
# binary_path = "/usr/local/bin/opencode"

[codex]
# binary_path = "/usr/local/bin/codex"

[flare]
# binary_path = "/usr/local/bin/flare"
"##;

fn is_hex_colour(value: &str) -> bool {
    value.len() == 7 && value.starts_with('#') && value[1..].chars().all(|c| c.is_ascii_hexdigit())
}

impl Config {
    pub fn path() -> anyhow::Result<PathBuf> {
        Ok(paths::config_dir()?.join("flare").join("config.toml"))
    }

    /// Load the config, falling back to defaults. The second element says why
    /// a file that existed could not be used as written.
    pub fn load() -> (Self, Option<String>) {
        let path = match Self::path() {
            Ok(path) => path,
            Err(err) => return (Self::default(), Some(format!("{err:#}"))),
        };
        Self::load_from(&path)
    }

    pub fn load_from(path: &Path) -> (Self, Option<String>) {
        let text = match std::fs::read_to_string(path) {
            Ok(text) => text,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
                return (Self::default(), None);
            }
            Err(err) => {
                return (Self::default(), Some(format!("{}: {err}", path.display())));
            }
        };

        let config: Self = match toml::from_str(&text) {
            Ok(config) => config,
            Err(err) => {
                return (Self::default(), Some(format!("{}: {err}", path.display())));
            }
        };

        match config.validate() {
            Ok(()) => (config, None),
            Err(err) => (config.clamped(), Some(format!("{}: {err}", path.display()))),
        }
    }

    pub fn validate(&self) -> anyhow::Result<()> {
        ensure!(
            SCALE_RANGE.contains(&self.notch.scale),
            "notch.scale must be between {} and {}, got {}",
            SCALE_RANGE.start(),
            SCALE_RANGE.end(),
            self.notch.scale
        );
        ensure!(
            self.poll.interval_secs >= MIN_POLL_SECS,
            "poll.interval_secs must be at least {MIN_POLL_SECS}, got {}",
            self.poll.interval_secs
        );
        ensure!(self.scan.window_days >= 1, "scan.window_days must be at least 1");
        ensure!(
            self.notch.gap <= MAX_GAP,
            "notch.gap must be at most {MAX_GAP}, got {}",
            self.notch.gap
        );
        for (key, value) in [
            ("notch.reveal_delay_ms", self.notch.reveal_delay_ms),
            ("notch.hide_delay_ms", self.notch.hide_delay_ms),
        ] {
            ensure!(value <= MAX_DELAY_MS, "{key} must be at most {MAX_DELAY_MS}, got {value}");
        }
        for (index, id) in self.providers.order.iter().enumerate() {
            ensure!(
                IDS.contains(&id.as_str()),
                "providers.order: unknown provider {id:?}; known: {}",
                IDS.join(", ")
            );
            ensure!(
                !self.providers.order[..index].contains(id),
                "providers.order lists {id:?} twice"
            );
        }
        for (key, value) in [
            ("aura.claude", &self.aura.claude),
            ("aura.codex", &self.aura.codex),
            ("aura.cursor", &self.aura.cursor),
            ("aura.opencode", &self.aura.opencode),
        ] {
            ensure!(is_hex_colour(value), "{key} must look like #RRGGBB, got {value:?}");
        }
        Ok(())
    }

    fn clamped(mut self) -> Self {
        self.notch.scale = if self.notch.scale.is_finite() {
            self.notch.scale.clamp(*SCALE_RANGE.start(), *SCALE_RANGE.end())
        } else {
            1.0
        };
        self.poll.interval_secs = self.poll.interval_secs.max(MIN_POLL_SECS);
        self.scan.window_days = self.scan.window_days.max(1);
        self.notch.gap = self.notch.gap.min(MAX_GAP);
        self.notch.reveal_delay_ms = self.notch.reveal_delay_ms.min(MAX_DELAY_MS);
        self.notch.hide_delay_ms = self.notch.hide_delay_ms.min(MAX_DELAY_MS);
        let mut order: Vec<String> = Vec::new();
        for id in &self.providers.order {
            if IDS.contains(&id.as_str()) && !order.contains(id) {
                order.push(id.clone());
            }
        }
        self.providers.order = order;
        let defaults = Aura::default();
        for (value, fallback) in [
            (&mut self.aura.claude, defaults.claude),
            (&mut self.aura.codex, defaults.codex),
            (&mut self.aura.cursor, defaults.cursor),
            (&mut self.aura.opencode, defaults.opencode),
        ] {
            if !is_hex_colour(value) {
                *value = fallback;
            }
        }
        self
    }

    /// Every provider id, in the configured order; any the order leaves out
    /// follow in their default place.
    pub fn provider_order(&self) -> Vec<&'static str> {
        let mut out: Vec<&'static str> = Vec::new();
        for name in &self.providers.order {
            if let Some(id) = IDS.iter().find(|id| **id == name.as_str()) {
                if !out.contains(id) {
                    out.push(id);
                }
            }
        }
        for id in IDS {
            if !out.contains(&id) {
                out.push(id);
            }
        }
        out
    }

    pub fn enabled(&self, provider_id: &str) -> bool {
        match provider_id {
            "claude" => self.providers.claude,
            "codex" => self.providers.codex,
            "cursor" => self.providers.cursor,
            "opencode" => self.providers.opencode,
            _ => false,
        }
    }

    pub fn scan_cutoff_secs(&self) -> i64 {
        let days = i64::from(self.scan.window_days.max(1));
        paths::now_secs() - days * 86_400
    }
}

/// Set one key in the config file, keeping everything else as written.
///
/// Refuses unknown keys and values the key cannot hold, and leaves the file
/// untouched when it does.
pub fn set_value(path: &Path, key: &str, raw: &str) -> anyhow::Result<()> {
    ensure!(KEYS.contains(&key), "unknown key {key:?}; known keys: {}", KEYS.join(", "));
    let (section, name) = key.split_once('.').context("every known key has a section")?;

    let text = match std::fs::read_to_string(path) {
        Ok(text) => text,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => String::new(),
        Err(err) => return Err(err).with_context(|| path.display().to_string()),
    };
    let doc: DocumentMut = text.parse().with_context(|| {
        format!("{} is not valid TOML; fix it by hand before using `flare config set`", path.display())
    })?;

    let candidates: Vec<Value> = if key == "providers.order" {
        // `claude,codex,cursor` or `["claude", "codex"]`, both accepted.
        let mut array = Array::new();
        for item in raw
            .trim()
            .trim_start_matches('[')
            .trim_end_matches(']')
            .split(|c: char| c == ',' || c.is_whitespace())
            .map(|item| item.trim().trim_matches('"').trim_matches('\''))
            .filter(|item| !item.is_empty())
        {
            array.push(item);
        }
        vec![Value::Array(array)]
    } else {
        // `42`, `1.5` and `true` as those types; anything else, or anything the
        // key will not take in that type, again as a string.
        let mut candidates = Vec::new();
        if let Ok(value) = raw.trim().parse::<Value>() {
            candidates.push(value);
        }
        candidates.push(Value::from(raw));
        candidates
    };

    let mut last_error = String::new();
    for candidate in candidates {
        let mut trial = doc.clone();
        write_key(&mut trial, section, name, candidate)?;
        let rendered = trial.to_string();
        match toml::from_str::<Config>(&rendered) {
            Ok(config) => {
                config.validate()?;
                return write_atomic(path, &rendered);
            }
            Err(err) => last_error = err.message().to_string(),
        }
    }
    bail!("{key}: {last_error}")
}

fn write_key(doc: &mut DocumentMut, section: &str, name: &str, value: Value) -> anyhow::Result<()> {
    let table = doc
        .entry(section)
        .or_insert(toml_edit::table())
        .as_table_like_mut()
        .with_context(|| format!("[{section}] in the config file is not a table"))?;
    match table.get_mut(name) {
        Some(Item::Value(existing)) => {
            let decor = existing.decor().clone();
            *existing = value;
            *existing.decor_mut() = decor;
        }
        _ => {
            table.insert(name, Item::Value(value));
        }
    }
    Ok(())
}

/// Replace a file in one step. A symlinked config is written through to its
/// target rather than replaced by a regular file.
pub fn write_atomic(path: &Path, contents: &str) -> anyhow::Result<()> {
    let target = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    let dir = target.parent().context("config path has no parent directory")?;
    std::fs::create_dir_all(dir).with_context(|| dir.display().to_string())?;
    let tmp = dir.join(format!(".config.toml.{}", std::process::id()));
    std::fs::write(&tmp, contents).with_context(|| tmp.display().to_string())?;
    std::fs::rename(&tmp, &target).with_context(|| target.display().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write(dir: &Path, body: &str) -> PathBuf {
        let path = dir.join("config.toml");
        std::fs::write(&path, body).expect("write config");
        path
    }

    #[test]
    fn a_missing_file_is_not_a_problem() {
        let dir = tempfile::tempdir().unwrap();
        let (config, problem) = Config::load_from(&dir.path().join("absent.toml"));
        assert!(problem.is_none());
        assert_eq!(config.data.mode, DataMode::Official);
        assert_eq!(config.notch.style, Style::Classic);
        assert_eq!(config.provider_order(), ["claude", "codex", "opencode", "cursor"]);
    }

    #[test]
    fn a_corrupt_file_falls_back_to_defaults_and_reports_why() {
        let dir = tempfile::tempdir().unwrap();
        let path = write(dir.path(), "this is not = valid = toml [[[");
        let (config, problem) = Config::load_from(&path);
        assert!(problem.is_some());
        assert_eq!(config.poll.interval_secs, 30);
    }

    #[test]
    fn reads_the_documented_fields() {
        let dir = tempfile::tempdir().unwrap();
        let path = write(
            dir.path(),
            "[data]\nmode = \"local\"\n\
             [notch]\nstyle = \"aura\"\nmount = \"floating\"\ngap = 12\nreveal = \"hover\"\nhide_delay_ms = 250\nedge = \"right\"\noffset = -40\nscale = 1.25\nscreen = \"DP-1\"\n\
             [compact]\nedge = \"bottom\"\noffset = 12\nopen_on = \"hover\"\n\
             [providers]\ncodex = false\norder = [\"cursor\", \"claude\"]\n\
             [aura]\nclaude = \"#112233\"\n",
        );
        let (config, problem) = Config::load_from(&path);
        assert!(problem.is_none(), "{problem:?}");
        assert_eq!(config.data.mode, DataMode::Local);
        assert_eq!(config.notch.style, Style::Aura);
        assert_eq!(config.notch.mount, Mount::Floating);
        assert_eq!(config.notch.gap, 12);
        assert_eq!(config.notch.reveal, Reveal::Hover);
        assert_eq!(config.notch.reveal_delay_ms, 80);
        assert_eq!(config.notch.hide_delay_ms, 250);
        assert_eq!(config.notch.edge, Edge::Right);
        assert_eq!(config.compact.edge, CompactEdge::Bottom);
        assert_eq!(config.compact.open_on, OpenOn::Hover);
        assert!(!config.enabled("codex"));
        assert_eq!(config.aura.claude, "#112233");
        assert_eq!(config.aura.codex, "#6E7BFF");
        assert_eq!(config.provider_order(), ["cursor", "claude", "codex", "opencode"]);
    }

    #[test]
    fn out_of_range_values_are_clamped_and_reported() {
        let dir = tempfile::tempdir().unwrap();
        let path = write(
            dir.path(),
            "[notch]\nscale = 9.0\n[providers]\norder = [\"claude\", \"nope\", \"claude\"]\n[aura]\ncodex = \"blue\"\n",
        );
        let (config, problem) = Config::load_from(&path);
        assert!(problem.is_some());
        assert_eq!(config.notch.scale, 2.0);
        assert_eq!(config.providers.order, ["claude"]);
        assert_eq!(config.aura.codex, "#6E7BFF");
    }

    #[test]
    fn the_template_describes_exactly_the_defaults() {
        let parsed: Config = toml::from_str(TEMPLATE).expect("template parses");
        assert_eq!(
            serde_json::to_value(parsed).unwrap(),
            serde_json::to_value(Config::default()).unwrap()
        );
        for key in KEYS {
            let (section, name) = key.split_once('.').unwrap();
            assert!(TEMPLATE.contains(&format!("[{section}]")), "{key} has no section");
            assert!(TEMPLATE.contains(name), "{key} is not documented");
        }
    }

    #[test]
    fn set_creates_the_file_and_keeps_comments_in_an_existing_one() {
        let dir = tempfile::tempdir().unwrap();
        let fresh = dir.path().join("nested").join("config.toml");
        set_value(&fresh, "notch.style", "aura").expect("set");
        assert_eq!(Config::load_from(&fresh).0.notch.style, Style::Aura);

        let path = write(dir.path(), TEMPLATE);
        set_value(&path, "notch.edge", "right").expect("set");
        let text = std::fs::read_to_string(&path).unwrap();
        assert!(text.contains("# Edge for classic and aura"));
        assert!(text.contains("edge = \"right\""));
        assert_eq!(text.lines().count(), TEMPLATE.lines().count());
    }

    #[test]
    fn set_refuses_what_the_key_cannot_hold_and_leaves_the_file_alone() {
        let dir = tempfile::tempdir().unwrap();
        let path = write(dir.path(), TEMPLATE);
        assert!(set_value(&path, "notch.edge", "top").is_err());
        assert!(set_value(&path, "notch.scale", "9").is_err());
        assert!(set_value(&path, "data.mode", "cloud").is_err());
        assert!(set_value(&path, "notch.mount", "side").is_err());
        assert!(set_value(&path, "notch.gap", "100").is_err());
        assert!(set_value(&path, "notch.reveal", "sometimes").is_err());
        assert!(set_value(&path, "notch.hide_delay_ms", "9000").is_err());
        assert!(set_value(&path, "aura.claude", "orange").is_err());
        assert!(set_value(&path, "providers.order", "claude,claude").is_err());
        assert!(set_value(&path, "notch.nope", "1").is_err());
        assert_eq!(std::fs::read_to_string(&path).unwrap(), TEMPLATE);
    }

    #[test]
    fn set_takes_numbers_booleans_lists_and_bare_strings() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("config.toml");
        set_value(&path, "notch.offset", "-40").unwrap();
        set_value(&path, "notch.scale", "1").unwrap();
        set_value(&path, "providers.codex", "false").unwrap();
        set_value(&path, "notch.screen", "1").unwrap();
        set_value(&path, "providers.order", "cursor, opencode claude").unwrap();
        set_value(&path, "aura.cursor", "#abcdef").unwrap();
        let (config, problem) = Config::load_from(&path);
        assert!(problem.is_none(), "{problem:?}");
        assert_eq!(config.notch.offset, -40);
        assert_eq!(config.notch.scale, 1.0);
        assert!(!config.providers.codex);
        assert_eq!(config.notch.screen, "1");
        assert_eq!(config.providers.order, ["cursor", "opencode", "claude"]);
        assert_eq!(config.aura.cursor, "#abcdef");
    }

    #[test]
    fn an_empty_binary_override_means_path_lookup() {
        let blank = Binary { binary_path: Some("  ".into()) };
        assert_eq!(blank.command("opencode"), "opencode");
        let set = Binary { binary_path: Some("/opt/opencode".into()) };
        assert_eq!(set.command("opencode"), "/opt/opencode");
    }
}
