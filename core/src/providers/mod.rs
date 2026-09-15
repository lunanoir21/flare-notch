//! Provider registry.
//!
//! A disabled provider is never constructed, so it performs no I/O at all
//! rather than being filtered out after the fact.

pub mod claude;
pub mod codex;
pub mod cursor;
pub mod opencode;

use crate::{Config, UsageProvider};

/// Every provider id flare knows about.
pub const IDS: [&str; 4] = ["claude", "codex", "cursor", "opencode"];

/// Every enabled provider, in the configured order.
pub fn all(config: &Config) -> Vec<Box<dyn UsageProvider>> {
    config
        .provider_order()
        .into_iter()
        .filter(|id| config.enabled(id))
        .filter_map(|id| by_id(id, config))
        .collect()
}

/// Look up a single provider by id, regardless of whether it is enabled.
pub fn by_id(id: &str, config: &Config) -> Option<Box<dyn UsageProvider>> {
    match id {
        "claude" => Some(Box::new(claude::Claude::new(config.clone()))),
        "codex" => Some(Box::new(codex::Codex::new(config.clone()))),
        "cursor" => Some(Box::new(cursor::Cursor::new(config.clone()))),
        "opencode" => Some(Box::new(opencode::OpenCode::new(config.clone()))),
        _ => None,
    }
}
