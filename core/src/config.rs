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

use crate::accounts;
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

/// black or white, or follow the system's light/dark preference. The QML
/// side owns "auto": it watches the desktop portal and picks light or dark
/// itself, the same way Quay's own theme does — this enum just carries the
/// user's choice of the three, untouched.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ThemeMode {
    #[default]
    Black,
    White,
    Auto,
}

/// What sits under a ring in classic and beside it in compact.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Label {
    /// How much of the window is used.
    #[default]
    Percent,
    /// How long until the window resets.
    Time,
    /// Both, the time smaller under the percentage.
    Both,
}

/// The widget's language. `auto` follows LC_ALL, LC_MESSAGES or LANG.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Language {
    #[default]
    Auto,
    En,
    Tr,
}

/// How a ring shows usage.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RingColor {
    /// Contrast only; a single accent colour appears just for a critical
    /// state (90% used, or exhausted).
    #[default]
    Monochrome,
    /// Each provider's own `[aura]` colour, on its ring too — not only in
    /// the aura style.
    Provider,
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

/// Whether the user has agreed to official mode reading Cursor's live
/// session out of the editor's own private state and replaying it against
/// cursor.com — the one provider where official mode borrows more than a
/// stored token (see `Consent` on [`Data::cursor_consent`]).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Consent {
    /// Not asked yet, or reset — the widget asks once, the next time
    /// official mode would need it.
    #[default]
    Unset,
    Granted,
    /// Asked and declined; Cursor stays out of official mode until this is
    /// changed by hand or from the settings page.
    Declined,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Data {
    pub mode: DataMode,
    pub cursor_consent: Consent,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Ui {
    pub language: Language,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Theme {
    pub mode: ThemeMode,
    pub ring_color: RingColor,
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
    pub label: Label,
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
            label: Label::Percent,
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
    pub antigravity: bool,
    pub kiro: bool,
    /// Drawing order, and the order aura steps through. Holds account ids
    /// (`claude:work`) too; one left out follows its provider.
    pub order: Vec<String>,
    /// Look for more logins in `~/.claude-<name>` and `~/.codex-<name>`.
    pub find_accounts: bool,
    /// Logins switched off one by one, by id; `claude` itself may be one.
    pub accounts_off: Vec<String>,
}

impl Default for Providers {
    fn default() -> Self {
        Self {
            claude: true,
            codex: true,
            cursor: true,
            opencode: true,
            antigravity: true,
            kiro: true,
            order: DEFAULT_ORDER.map(String::from).to_vec(),
            find_accounts: true,
            accounts_off: Vec::new(),
        }
    }
}

const DEFAULT_ORDER: [&str; 6] = ["claude", "codex", "opencode", "cursor", "antigravity", "kiro"];

/// The colour aura takes on for each provider, as `#RRGGBB`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Aura {
    pub claude: String,
    pub codex: String,
    pub cursor: String,
    pub opencode: String,
    pub antigravity: String,
    pub kiro: String,
}

impl Default for Aura {
    fn default() -> Self {
        Self {
            claude: "#D97757".into(),
            codex: "#6E7BFF".into(),
            cursor: "#3DD6C6".into(),
            opencode: "#C9CED6".into(),
            antigravity: "#4F8DF7".into(),
            kiro: "#9046FF".into(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Sessions {
    /// List open sessions in the widget at all.
    pub show: bool,
}

impl Default for Sessions {
    fn default() -> Self {
        Self { show: true }
    }
}

/// Another login for a provider whose CLI can keep one elsewhere, as
/// `[[account]]` in the file.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct AccountEntry {
    /// `claude` or `codex`.
    pub provider: String,
    /// Lower-case letters, digits, `-` and `_`; the account id is `<provider>:<name>`.
    pub name: String,
    /// The directory the CLI keeps this login in: what `CLAUDE_CONFIG_DIR` or
    /// `CODEX_HOME` is set to when it runs. `~/` is the home directory.
    pub home: String,
    /// Aura's colour for this login, as `#RRGGBB`; the provider's otherwise.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub color: Option<String>,
}

/// The usage panel.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Usage {
    /// Also list, and read, the providers switched off in the widget.
    pub all_providers: bool,
}

/// Desktop notifications, sent by `flare watch`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Notify {
    /// A session starts waiting on you.
    pub waiting: bool,
    /// A limit crosses `limit_at` percent.
    pub limit: bool,
    pub limit_at: u32,
    /// A limit that had been used resets.
    pub reset: bool,
}

impl Default for Notify {
    fn default() -> Self {
        Self { waiting: true, limit: true, limit_at: 90, reset: true }
    }
}

impl Notify {
    pub fn any(&self) -> bool {
        self.waiting || self.limit || self.reset
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
    pub theme: Theme,
    pub ui: Ui,
    pub notch: Notch,
    pub compact: Compact,
    pub providers: Providers,
    pub sessions: Sessions,
    pub usage: Usage,
    pub notify: Notify,
    pub aura: Aura,
    pub poll: Poll,
    pub scan: Scan,
    pub opencode: Binary,
    pub codex: Binary,
    /// Where to find the `claude` CLI for token renewal, instead of
    /// searching PATH and a fixed list of well-known, user-writable install
    /// directories — all of which run whatever they find there.
    pub claude: Binary,
    /// `kiro-cli`, run only to renew an expiring sign-in, as `claude` is.
    pub kiro: Binary,
    /// The flare binary itself, for a compositor that starts Quickshell
    /// without the login shell's PATH.
    pub flare: Binary,
    /// `[[account]]`: logins beyond the ones `providers.find_accounts` finds.
    #[serde(rename = "account")]
    pub accounts: Vec<AccountEntry>,
}

pub const SCALE_RANGE: RangeInclusive<f64> = 0.5..=2.0;
pub const MIN_POLL_SECS: u64 = 5;
pub const MAX_GAP: u32 = 64;
pub const MAX_DELAY_MS: u32 = 5000;
pub const LIMIT_AT_RANGE: RangeInclusive<u32> = 50..=100;

/// Every key `flare config set` accepts.
pub const KEYS: &[&str] = &[
    "data.mode",
    "data.cursor_consent",
    "theme.mode",
    "theme.ring_color",
    "ui.language",
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
    "notch.label",
    "compact.edge",
    "compact.offset",
    "compact.open_on",
    "providers.claude",
    "providers.codex",
    "providers.cursor",
    "providers.opencode",
    "providers.antigravity",
    "providers.kiro",
    "providers.order",
    "providers.find_accounts",
    "providers.accounts_off",
    "sessions.show",
    "usage.all_providers",
    "notify.waiting",
    "notify.limit",
    "notify.limit_at",
    "notify.reset",
    "aura.claude",
    "aura.codex",
    "aura.cursor",
    "aura.opencode",
    "aura.antigravity",
    "aura.kiro",
    "poll.interval_secs",
    "scan.window_days",
    "opencode.binary_path",
    "codex.binary_path",
    "claude.binary_path",
    "kiro.binary_path",
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
# Cursor is the one provider where official mode reads more than a stored
# token: a live session cookie, out of the Cursor editor's own private state.
# The widget asks once before ever doing that; this records the answer.
#   unset     not asked yet — asked once, the next time it would matter
#   granted   go ahead and read it
#   declined  don't; Cursor stays out of official mode until this changes
cursor_consent = "unset"

[theme]
# black, white, or auto (follow the system's light/dark preference).
mode = "black"
# How rings show usage:
#   monochrome  contrast only; a single accent colour appears just for a
#               critical state (90% used, or exhausted)
#   provider    each provider's own [aura] colour, on its ring too
ring_color = "monochrome"

[ui]
# auto (follow LC_ALL / LC_MESSAGES / LANG), en or tr.
language = "auto"

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
# Under each ring: percent (used), time (until it resets), or both.
label = "percent"

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
antigravity = true
kiro = true
# The order cells are drawn in, and the order aura steps through. Another
# login goes in by its id, e.g. "claude:work"; one left out follows its provider.
order = ["claude", "codex", "opencode", "cursor", "antigravity", "kiro"]
# More than one Claude Code or Codex login, each a ring of its own: a directory
# ~/.claude-<name> or ~/.codex-<name> holding a sign-in is found on its own
# (sign in with `CLAUDE_CONFIG_DIR=~/.claude-work claude`, or
# `CODEX_HOME=~/.codex-work codex login`) and becomes "claude:work".
find_accounts = true
# Logins to leave out one by one, by id, e.g. ["claude:work"].
accounts_off = []

[aura]
# The colour aura takes on for each provider.
claude = "#D97757"
codex = "#6E7BFF"
cursor = "#3DD6C6"
opencode = "#C9CED6"
antigravity = "#4F8DF7"
kiro = "#9046FF"

[sessions]
# List the Claude Code sessions running right now in the widget.
show = true

[usage]
# List the providers switched off above in the usage panel too. They are then
# read like the rest, just not drawn in the widget.
all_providers = false

[notify]
# Desktop notifications, sent by `flare watch`, which the widget starts while
# any of these is on.
#   waiting   a session stops and waits on you; the notification jumps to it
#   limit     a limit reaches limit_at percent (50 to 100)
#   reset     a limit you had been using resets
waiting = true
limit = true
limit_at = 90
reset = true

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

# Claude Code's own CLI, used only to renew an expiring token. Pin this
# instead of trusting whatever "claude" resolves to first on PATH.
[claude]
# binary_path = "/usr/local/bin/claude"

# kiro-cli, used only to renew an expiring sign-in (`kiro-cli whoami`).
[kiro]
# binary_path = "/usr/local/bin/kiro-cli"

[flare]
# binary_path = "/usr/local/bin/flare"

# A login that lives somewhere find_accounts does not look, one block each.
# [[account]]
# provider = "claude"        # or "codex"
# name = "work"              # its id becomes "claude:work"
# home = "~/work/.claude"    # what CLAUDE_CONFIG_DIR / CODEX_HOME is set to
# color = "#E0A458"          # optional; aura's colour for this login
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
            LIMIT_AT_RANGE.contains(&self.notify.limit_at),
            "notify.limit_at must be between {} and {}, got {}",
            LIMIT_AT_RANGE.start(),
            LIMIT_AT_RANGE.end(),
            self.notify.limit_at
        );
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
        for (key, list) in [("providers.order", &self.providers.order), ("providers.accounts_off", &self.providers.accounts_off)] {
            for (index, id) in list.iter().enumerate() {
                ensure!(
                    accounts::valid_id(id),
                    "{key}: unknown provider {id:?}; known: {}, or claude:<name> / codex:<name>",
                    IDS.join(", ")
                );
                ensure!(!list[..index].contains(id), "{key} lists {id:?} twice");
            }
        }
        for (index, entry) in self.accounts.iter().enumerate() {
            ensure!(
                accounts::KINDS.contains(&entry.provider.as_str()),
                "[[account]] {:?}: provider must be one of {}, got {:?}",
                entry.name,
                accounts::KINDS.join(", "),
                entry.provider
            );
            ensure!(
                accounts::valid_name(&entry.name),
                "[[account]] name {:?}: use lower-case letters, digits, - and _, at most 32",
                entry.name
            );
            ensure!(!entry.home.trim().is_empty(), "[[account]] {:?}: home is empty", entry.name);
            if let Some(color) = &entry.color {
                ensure!(is_hex_colour(color), "[[account]] {:?}: color must look like #RRGGBB, got {color:?}", entry.name);
            }
            ensure!(
                !self.accounts[..index].iter().any(|other| other.provider == entry.provider && other.name == entry.name),
                "[[account]] {}:{} is listed twice",
                entry.provider,
                entry.name
            );
        }
        for (key, value) in [
            ("aura.claude", &self.aura.claude),
            ("aura.codex", &self.aura.codex),
            ("aura.cursor", &self.aura.cursor),
            ("aura.opencode", &self.aura.opencode),
            ("aura.antigravity", &self.aura.antigravity),
            ("aura.kiro", &self.aura.kiro),
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
        self.notify.limit_at = self.notify.limit_at.clamp(*LIMIT_AT_RANGE.start(), *LIMIT_AT_RANGE.end());
        self.notch.gap = self.notch.gap.min(MAX_GAP);
        self.notch.reveal_delay_ms = self.notch.reveal_delay_ms.min(MAX_DELAY_MS);
        self.notch.hide_delay_ms = self.notch.hide_delay_ms.min(MAX_DELAY_MS);
        for list in [&mut self.providers.order, &mut self.providers.accounts_off] {
            let mut kept: Vec<String> = Vec::new();
            for id in list.iter() {
                if accounts::valid_id(id) && !kept.contains(id) {
                    kept.push(id.clone());
                }
            }
            *list = kept;
        }
        let mut entries: Vec<AccountEntry> = Vec::new();
        for mut entry in std::mem::take(&mut self.accounts) {
            let usable = accounts::KINDS.contains(&entry.provider.as_str())
                && accounts::valid_name(&entry.name)
                && !entry.home.trim().is_empty()
                && !entries.iter().any(|e| e.provider == entry.provider && e.name == entry.name);
            if usable {
                entry.color = entry.color.filter(|c| is_hex_colour(c));
                entries.push(entry);
            }
        }
        self.accounts = entries;
        let defaults = Aura::default();
        for (value, fallback) in [
            (&mut self.aura.claude, defaults.claude),
            (&mut self.aura.codex, defaults.codex),
            (&mut self.aura.cursor, defaults.cursor),
            (&mut self.aura.opencode, defaults.opencode),
            (&mut self.aura.antigravity, defaults.antigravity),
            (&mut self.aura.kiro, defaults.kiro),
        ] {
            if !is_hex_colour(value) {
                *value = fallback;
            }
        }
        self
    }

    /// Every provider id and every other login on this machine, in the
    /// configured order: a provider the order leaves out follows in its
    /// default place, and a login it leaves out follows its provider's last.
    pub fn provider_order(&self) -> Vec<String> {
        let accounts: Vec<String> = accounts::extra(self).into_iter().map(|a| a.id).collect();
        self.order_with(&accounts)
    }

    fn order_with(&self, accounts: &[String]) -> Vec<String> {
        let here = |id: &str| IDS.contains(&id) || accounts.iter().any(|a| a == id);
        let mut out: Vec<String> = Vec::new();
        for id in &self.providers.order {
            if here(id) && !out.contains(id) {
                out.push(id.clone());
            }
        }
        for id in IDS {
            if !out.iter().any(|o| o == id) {
                out.push(id.to_string());
            }
        }
        for account in accounts {
            if out.contains(account) {
                continue;
            }
            let provider = accounts::split(account).0;
            let at = out
                .iter()
                .rposition(|o| accounts::split(o).0 == provider)
                .map_or(out.len(), |i| i + 1);
            out.insert(at, account.clone());
        }
        out
    }

    /// Whether a provider or one login is shown: its provider switched on, and
    /// the login not switched off on its own.
    pub fn enabled(&self, id: &str) -> bool {
        let on = match accounts::split(id).0 {
            "claude" => self.providers.claude,
            "codex" => self.providers.codex,
            "cursor" => self.providers.cursor,
            "opencode" => self.providers.opencode,
            "antigravity" => self.providers.antigravity,
            "kiro" => self.providers.kiro,
            _ => false,
        };
        on && !self.providers.accounts_off.iter().any(|off| off == id)
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

    let candidates: Vec<Value> = if key == "providers.order" || key == "providers.accounts_off" {
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
        assert_eq!(config.data.cursor_consent, Consent::Unset);
        assert_eq!(config.theme.mode, ThemeMode::Black);
        assert_eq!(config.theme.ring_color, RingColor::Monochrome);
        assert_eq!(config.notch.style, Style::Classic);
        assert_eq!(config.provider_order(), ["claude", "codex", "opencode", "cursor", "antigravity", "kiro"]);
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
            "[data]\nmode = \"local\"\ncursor_consent = \"granted\"\n\
             [theme]\nmode = \"white\"\nring_color = \"provider\"\n\
             [notch]\nstyle = \"aura\"\nmount = \"floating\"\ngap = 12\nreveal = \"hover\"\nhide_delay_ms = 250\nedge = \"right\"\noffset = -40\nscale = 1.25\nscreen = \"DP-1\"\n\
             [compact]\nedge = \"bottom\"\noffset = 12\nopen_on = \"hover\"\n\
             [providers]\ncodex = false\norder = [\"cursor\", \"claude\"]\n\
             [aura]\nclaude = \"#112233\"\n",
        );
        let (config, problem) = Config::load_from(&path);
        assert!(problem.is_none(), "{problem:?}");
        assert_eq!(config.data.mode, DataMode::Local);
        assert_eq!(config.data.cursor_consent, Consent::Granted);
        assert_eq!(config.theme.mode, ThemeMode::White);
        assert_eq!(config.theme.ring_color, RingColor::Provider);
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
        assert_eq!(config.provider_order(), ["cursor", "claude", "codex", "opencode", "antigravity", "kiro"]);
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
        assert!(set_value(&path, "theme.mode", "purple").is_err());
        assert!(set_value(&path, "theme.ring_color", "rainbow").is_err());
        assert!(set_value(&path, "data.cursor_consent", "maybe").is_err());
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
        set_value(&path, "theme.mode", "auto").unwrap();
        set_value(&path, "ui.language", "en").unwrap();
        set_value(&path, "notch.label", "both").unwrap();
        set_value(&path, "notify.limit_at", "80").unwrap();
        set_value(&path, "sessions.show", "false").unwrap();
        set_value(&path, "usage.all_providers", "true").unwrap();
        assert!(set_value(&path, "notify.limit_at", "20").is_err());
        assert!(set_value(&path, "ui.language", "de").is_err());
        let (config, problem) = Config::load_from(&path);
        assert!(problem.is_none(), "{problem:?}");
        assert_eq!(config.theme.mode, ThemeMode::Auto);
        assert_eq!(config.ui.language, Language::En);
        assert_eq!(config.notch.label, Label::Both);
        assert_eq!(config.notify.limit_at, 80);
        assert!(!config.sessions.show);
        assert!(config.usage.all_providers);
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

    #[test]
    fn a_login_the_order_leaves_out_follows_its_provider() {
        let mut config = Config::default();
        config.providers.order = vec!["codex".into(), "claude:work".into(), "claude".into()];
        let accounts = ["claude:work".to_string(), "claude:side".to_string(), "codex:home".to_string()];
        assert_eq!(
            config.order_with(&accounts),
            ["codex", "codex:home", "claude:work", "claude", "claude:side", "cursor", "opencode", "antigravity", "kiro"]
        );
        // A login named in the order but not on this machine is skipped.
        assert_eq!(config.order_with(&[])[..2], ["codex", "claude"]);
    }

    #[test]
    fn a_login_is_shown_while_its_provider_is_on_and_it_is_not_switched_off() {
        let mut config = Config::default();
        config.providers.accounts_off = vec!["claude:work".into()];
        assert!(config.enabled("claude"));
        assert!(config.enabled("claude:side"));
        assert!(!config.enabled("claude:work"));
        config.providers.claude = false;
        assert!(!config.enabled("claude:side"));
        config.providers.claude = true;
        config.providers.accounts_off = vec!["claude".into()];
        assert!(!config.enabled("claude"));
        assert!(config.enabled("claude:side"));
    }

    #[test]
    fn accounts_are_read_from_the_file_and_checked() {
        let dir = tempfile::tempdir().expect("temp dir");
        let path = write(
            dir.path(),
            r##"
[providers]
order = ["claude:work", "claude"]
accounts_off = ["codex:old"]

[[account]]
provider = "claude"
name = "work"
home = "~/work/.claude"
color = "#E0A458"
"##,
        );
        let (config, problem) = Config::load_from(&path);
        assert!(problem.is_none(), "{problem:?}");
        assert_eq!(config.accounts.len(), 1);
        assert_eq!(config.accounts[0].color.as_deref(), Some("#E0A458"));
        assert_eq!(config.providers.accounts_off, ["codex:old"]);

        let bad = write(
            dir.path(),
            r#"
[providers]
order = ["cursor:work", "claude"]

[[account]]
provider = "cursor"
name = "Work"
home = ""
"#,
        );
        let (config, problem) = Config::load_from(&bad);
        assert!(problem.is_some());
        assert_eq!(config.providers.order, ["claude"]);
        assert!(config.accounts.is_empty());
    }

    #[test]
    fn logins_are_switched_off_through_config_set() {
        let dir = tempfile::tempdir().expect("temp dir");
        let path = dir.path().join("config.toml");
        set_value(&path, "providers.accounts_off", "claude:work,codex").unwrap();
        set_value(&path, "providers.find_accounts", "false").unwrap();
        assert!(set_value(&path, "providers.accounts_off", "cursor:x").is_err());
        let (config, problem) = Config::load_from(&path);
        assert!(problem.is_none(), "{problem:?}");
        assert_eq!(config.providers.accounts_off, ["claude:work", "codex"]);
        assert!(!config.providers.find_accounts);
        set_value(&path, "providers.accounts_off", "").unwrap();
        assert!(Config::load_from(&path).0.providers.accounts_off.is_empty());
    }
}
