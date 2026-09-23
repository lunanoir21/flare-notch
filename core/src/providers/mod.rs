//! Provider registry.
//!
//! A disabled provider is never constructed, so it performs no I/O at all
//! rather than being filtered out after the fact.

pub mod antigravity;
pub mod claude;
pub mod codex;
pub mod cursor;
pub mod kiro;
pub mod opencode;

use crate::accounts;
use crate::{Config, UsageProvider};

/// Every provider flare knows about. Another login of one is `<id>:<name>`.
pub const IDS: [&str; 6] = ["claude", "codex", "cursor", "opencode", "antigravity", "kiro"];

/// Every enabled provider, in the configured order.
pub fn all(config: &Config) -> Vec<Box<dyn UsageProvider>> {
    config
        .provider_order()
        .into_iter()
        .filter(|id| config.enabled(id))
        .filter_map(|id| by_id(&id, config))
        .collect()
}

/// What the widget reads: every enabled provider, and with
/// `usage.all_providers` the switched-off ones too, for the usage panel.
pub fn for_widget(config: &Config) -> Vec<Box<dyn UsageProvider>> {
    config
        .provider_order()
        .into_iter()
        .filter(|id| config.enabled(id) || config.usage.all_providers)
        .filter_map(|id| by_id(&id, config))
        .collect()
}

/// Look up a single provider, or one login of it, by id, regardless of
/// whether it is enabled.
pub fn by_id(id: &str, config: &Config) -> Option<Box<dyn UsageProvider>> {
    if !accounts::valid_id(id) {
        return None;
    }
    match accounts::split(id).0 {
        "claude" => Some(Box::new(claude::Claude::new(config.clone(), accounts::lookup(config, id)?))),
        "codex" => Some(Box::new(codex::Codex::new(config.clone(), accounts::lookup(config, id)?))),
        "cursor" => Some(Box::new(cursor::Cursor::new(config.clone()))),
        "opencode" => Some(Box::new(opencode::OpenCode::new(config.clone()))),
        "antigravity" => Some(Box::new(antigravity::Antigravity::new(config.clone()))),
        "kiro" => Some(Box::new(kiro::Kiro::new(config.clone()))),
        _ => None,
    }
}
