//! More than one login for a provider whose CLI can be pointed at another
//! directory for its sign-in: Claude Code (`CLAUDE_CONFIG_DIR`) and Codex
//! (`CODEX_HOME`).
//!
//! The default login keeps the plain provider id (`claude`), so a config, the
//! state files and the history written before accounts existed carry on as
//! they are. Another login is `<provider>:<name>` (`claude:work`): a directory
//! `~/.claude-<name>` or `~/.codex-<name>` holding a sign-in, or an
//! `[[account]]` entry in the config for one that lives anywhere else.

use std::path::{Path, PathBuf};

use serde::Serialize;

use crate::providers::IDS;
use crate::{Config, paths};

/// Providers that can have more than one login.
pub const KINDS: [&str; 2] = ["claude", "codex"];

const NAME_MAX: usize = 32;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Origin {
    /// The login the CLI uses when nothing points it elsewhere.
    Default,
    /// A `~/.claude-<name>` or `~/.codex-<name>` directory with a sign-in in it.
    Found,
    /// An `[[account]]` entry in the config.
    Config,
}

impl Origin {
    /// For `flare doctor`.
    pub fn describe(self) -> &'static str {
        match self {
            Self::Default => "the default login",
            Self::Found => "found in the home directory",
            Self::Config => "from [[account]] in the config",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Account {
    /// `claude`, or `claude:work`.
    pub id: String,
    pub provider: &'static str,
    /// None for the default login.
    pub name: Option<String>,
    /// The directory the CLI keeps this login in.
    pub home: PathBuf,
    /// Aura's colour for this login, over the provider's own.
    pub color: Option<String>,
    pub origin: Origin,
}

impl Account {
    /// The login a provider's CLI uses unless told otherwise.
    pub fn default_for(provider: &str) -> Option<Self> {
        let (provider, home) = match provider {
            "claude" => ("claude", paths::claude_home().ok()?),
            "codex" => ("codex", paths::codex_home().ok()?),
            _ => return None,
        };
        Some(Self {
            id: provider.to_string(),
            provider,
            name: None,
            home,
            color: None,
            origin: Origin::Default,
        })
    }

    pub fn is_default(&self) -> bool {
        self.name.is_none()
    }

    /// The variable that points the provider's CLI at this login's directory.
    pub fn home_var(&self) -> &'static str {
        match self.provider {
            "claude" => "CLAUDE_CONFIG_DIR",
            _ => "CODEX_HOME",
        }
    }
}

/// `claude:work` → (`claude`, Some(`work`)); `claude` → (`claude`, None).
pub fn split(id: &str) -> (&str, Option<&str>) {
    match id.split_once(':') {
        Some((provider, name)) => (provider, Some(name)),
        None => (id, None),
    }
}

/// Lower-case letters, digits, `-` and `_`, starting with a letter or digit:
/// it ends up in file names, IPC calls and keybinds.
pub fn valid_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= NAME_MAX
        && name.starts_with(|c: char| c.is_ascii_lowercase() || c.is_ascii_digit())
        && name
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-' || c == '_')
}

/// An id the config may name, whether or not that login exists here.
pub fn valid_id(id: &str) -> bool {
    match split(id) {
        (provider, None) => IDS.contains(&provider),
        (provider, Some(name)) => KINDS.contains(&provider) && valid_name(name),
    }
}

/// The login an id names: the default one for a plain provider id, otherwise
/// one of `extra`.
pub fn lookup(config: &Config, id: &str) -> Option<Account> {
    match split(id) {
        (provider, None) => Account::default_for(provider),
        (_, Some(_)) => extra(config).into_iter().find(|account| account.id == id),
    }
}

/// Every provider's default login, then every other one, for `flare config get`.
pub fn all(config: &Config) -> Vec<Account> {
    KINDS
        .iter()
        .filter_map(|provider| Account::default_for(provider))
        .chain(extra(config))
        .collect()
}

/// Every login beyond the default ones: the config's `[[account]]` entries,
/// then the directories found in the home directory. A directory that is
/// already some login's home is not counted twice.
pub fn extra(config: &Config) -> Vec<Account> {
    let defaults: Vec<Account> = KINDS.iter().filter_map(|provider| Account::default_for(provider)).collect();
    let taken = |list: &[Account], candidate: &Account| {
        list.iter()
            .chain(&defaults)
            .any(|other| other.id == candidate.id || same_dir(&other.home, &candidate.home))
    };

    let mut out: Vec<Account> = Vec::new();
    for account in listed(config) {
        if !taken(&out, &account) {
            out.push(account);
        }
    }
    if config.providers.find_accounts {
        if let Ok(home) = paths::home_dir() {
            for account in found(&home) {
                if !taken(&out, &account) {
                    out.push(account);
                }
            }
        }
    }
    out
}

/// The config's `[[account]]` entries that name a provider with accounts and
/// a usable name; `Config::validate` reports the rest.
fn listed(config: &Config) -> Vec<Account> {
    config
        .accounts
        .iter()
        .filter_map(|entry| {
            let provider = *KINDS.iter().find(|kind| **kind == entry.provider)?;
            if !valid_name(&entry.name) || entry.home.trim().is_empty() {
                return None;
            }
            Some(Account {
                id: format!("{provider}:{}", entry.name),
                provider,
                name: Some(entry.name.clone()),
                home: expand_home(entry.home.trim()),
                color: entry.color.clone(),
                origin: Origin::Config,
            })
        })
        .collect()
}

/// `~/.claude-<name>` and `~/.codex-<name>` directories that hold a sign-in,
/// sorted by id. The sign-in file is what tells a login from a backup copy.
fn found(home: &Path) -> Vec<Account> {
    let Ok(entries) = std::fs::read_dir(home) else {
        return Vec::new();
    };
    let mut out: Vec<Account> = entries
        .flatten()
        .filter_map(|entry| {
            let file_name = entry.file_name();
            let file_name = file_name.to_str()?;
            let (provider, marker, rest) = if let Some(rest) = file_name.strip_prefix(".claude-") {
                ("claude", ".credentials.json", rest)
            } else {
                ("codex", "auth.json", file_name.strip_prefix(".codex-")?)
            };
            let name = rest.to_ascii_lowercase();
            let dir = entry.path();
            if !valid_name(&name) || !dir.is_dir() || !dir.join(marker).is_file() {
                return None;
            }
            Some(Account {
                id: format!("{provider}:{name}"),
                provider,
                name: Some(name),
                home: dir,
                color: None,
                origin: Origin::Found,
            })
        })
        .collect();
    out.sort_by(|a, b| a.id.cmp(&b.id));
    out
}

/// `~/x` and `~` under the home directory; anything else as written.
pub fn expand_home(path: &str) -> PathBuf {
    let home = paths::home_dir().ok();
    match (path, home) {
        ("~", Some(home)) => home,
        (path, Some(home)) if path.starts_with("~/") => home.join(&path[2..]),
        (path, _) => PathBuf::from(path),
    }
}

/// The same directory, through symlinks too.
pub fn same_dir(a: &Path, b: &Path) -> bool {
    match (std::fs::canonicalize(a), std::fs::canonicalize(b)) {
        (Ok(a), Ok(b)) => a == b,
        _ => a == b,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_split_into_provider_and_name() {
        assert_eq!(split("claude"), ("claude", None));
        assert_eq!(split("claude:work"), ("claude", Some("work")));
    }

    #[test]
    fn only_providers_with_accounts_take_a_name() {
        assert!(valid_id("claude"));
        assert!(valid_id("cursor"));
        assert!(valid_id("claude:work"));
        assert!(valid_id("codex:side-2"));
        assert!(!valid_id("cursor:work"));
        assert!(!valid_id("claude:"));
        assert!(!valid_id("claude:Work"));
        assert!(!valid_id("claude:-x"));
        assert!(!valid_id("claude:a/b"));
        assert!(!valid_id("nope"));
    }

    #[test]
    fn a_login_directory_needs_its_sign_in_to_count() {
        let home = tempfile::tempdir().unwrap();
        for dir in [".claude-work", ".claude-backup", ".codex-side", ".claude-Bad Name", ".claude"] {
            std::fs::create_dir_all(home.path().join(dir)).unwrap();
        }
        std::fs::write(home.path().join(".claude-work/.credentials.json"), "{}").unwrap();
        std::fs::write(home.path().join(".codex-side/auth.json"), "{}").unwrap();
        std::fs::write(home.path().join(".claude-Bad Name/.credentials.json"), "{}").unwrap();
        std::fs::write(home.path().join(".claude/.credentials.json"), "{}").unwrap();
        std::fs::write(home.path().join(".claude-file"), "not a directory").unwrap();

        let ids: Vec<String> = found(home.path()).into_iter().map(|a| a.id).collect();
        assert_eq!(ids, ["claude:work", "codex:side"]);
        assert!(found(home.path()).iter().all(|a| a.origin == Origin::Found));
    }

    #[test]
    fn a_found_name_is_folded_to_lower_case() {
        let home = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(home.path().join(".claude-Work")).unwrap();
        std::fs::write(home.path().join(".claude-Work/.credentials.json"), "{}").unwrap();
        assert_eq!(found(home.path())[0].id, "claude:work");
    }

    #[test]
    fn config_entries_become_accounts_and_bad_ones_are_skipped() {
        let dir = tempfile::tempdir().unwrap();
        let mut config = Config::default();
        config.providers.find_accounts = false;
        let entry = |provider: &str, name: &str, home: &str| crate::config::AccountEntry {
            provider: provider.into(),
            name: name.into(),
            home: home.into(),
            color: None,
        };
        let work = dir.path().join("work").display().to_string();
        config.accounts = vec![
            entry("claude", "work", &work),
            entry("cursor", "work", &work),
            entry("claude", "Bad", &work),
            entry("codex", "empty", "  "),
            // The same directory under a second name counts once.
            entry("claude", "again", &work),
        ];
        let accounts = extra(&config);
        assert_eq!(accounts.len(), 1);
        assert_eq!(accounts[0].id, "claude:work");
        assert_eq!(accounts[0].home, dir.path().join("work"));
        assert_eq!(accounts[0].origin, Origin::Config);
        assert_eq!(lookup(&config, "claude:work").map(|a| a.home), Some(dir.path().join("work")));
        assert!(lookup(&config, "claude:nope").is_none());
    }
}
