//! `flare doctor`: plain text, one block per provider.
//!
//! What someone runs when the widget shows nothing for a provider. It says
//! where flare looked and what it found, never the value of a secret.

use flare_core::providers::{self, claude, codex, cursor, opencode};
use flare_core::{Config, Fetch, Status};

pub fn run(config: &Config, config_problem: Option<&str>, ctx: &Fetch) {
    report_config(config, config_problem);
    for id in config.provider_order() {
        println!();
        let probe = match id {
            "claude" => claude::probe(),
            "codex" => codex::probe(),
            "cursor" => cursor::probe(),
            "opencode" => opencode::probe(),
            _ => Vec::new(),
        };
        if !config.enabled(id) {
            println!("[{id}] disabled in the config");
        }
        for line in probe {
            println!("[{id}] {line}");
        }
        report_snapshot(id, config, ctx);
    }
}

fn report_config(config: &Config, config_problem: Option<&str>) {
    match Config::path() {
        Ok(path) if path.exists() => println!("[config] file: {}", path.display()),
        Ok(path) => println!("[config] file: not present, defaults in use ({})", path.display()),
        Err(err) => println!("[config] file: path unresolved ({err:#})"),
    }
    if let Some(problem) = config_problem {
        println!("[config] PROBLEM: {problem}");
    }
    println!("[config] data: {}", serde_name(&config.data.mode));
    println!(
        "[config] style: {} · notch {} {:+}px ×{} · compact {} {:+}px, opens on {}",
        serde_name(&config.notch.style),
        serde_name(&config.notch.edge),
        config.notch.offset,
        config.notch.scale,
        serde_name(&config.compact.edge),
        config.compact.offset,
        serde_name(&config.compact.open_on),
    );
    println!("[config] order: {}", config.provider_order().join(" → "));
    println!(
        "[config] refresh every {}s, tokens over {} day(s)",
        config.poll.interval_secs, config.scan.window_days
    );
}

fn serde_name<T: serde::Serialize>(value: &T) -> String {
    serde_json::to_value(value)
        .ok()
        .and_then(|v| v.as_str().map(str::to_string))
        .unwrap_or_default()
}

fn format_duration(secs: i64) -> String {
    match secs {
        i64::MIN..=0 => "now".into(),
        1..=90 => format!("{secs}s"),
        91..=5399 => format!("{}m", secs / 60),
        5400..=172_799 => format!("{}h {}m", secs / 3600, secs % 3600 / 60),
        _ => format!("{}d", secs / 86_400),
    }
}

fn report_snapshot(id: &str, config: &Config, ctx: &Fetch) {
    let Some(provider) = providers::by_id(id, config) else { return };
    let usage = match provider.fetch(ctx) {
        Ok(usage) => usage,
        Err(err) => {
            println!("[{id}] FETCH FAILED {err:#}");
            return;
        }
    };
    if usage.status == Status::Absent {
        println!("[{id}] not installed — no cell is shown");
        return;
    }
    let age = usage
        .fetched_at
        .map(|at| match ctx.now - at {
            secs if secs <= 0 => ", read just now".to_string(),
            secs => format!(", read {} ago", format_duration(secs)),
        })
        .unwrap_or_default();
    println!(
        "[{id}] status: {} · source {}{} · plan {} · account {}",
        serde_name(&usage.status),
        usage.source,
        age,
        usage.plan.as_deref().unwrap_or("unknown"),
        usage.account.as_deref().unwrap_or("unknown")
    );
    if let Some(note) = &usage.note {
        println!("[{id}] note: {note}");
    }
    if let Some(until) = usage.backoff_until {
        println!("[{id}] backing off for {}", format_duration(until - ctx.now));
    }
    for window in &usage.windows {
        let headline = if usage.headline.as_deref() == Some(window.id.as_str()) { " ◉" } else { "" };
        let group = window.group.as_deref().map(|g| format!("{g} · ")).unwrap_or_default();
        let resets = if window.reset_elapsed {
            "reset has passed since this reading".to_string()
        } else {
            window
                .resets_in_secs
                .map(|secs| format!("resets in {}", format_duration(secs)))
                .unwrap_or_else(|| "no reset time".into())
        };
        println!(
            "[{id}]   {group}{}{headline}: {:.0}% used, {resets}",
            window.label,
            window.used * 100.0
        );
    }
    if usage.metered && usage.windows.is_empty() {
        println!("[{id}]   no usage windows");
    }
    if let Some(tokens) = usage.tokens_today {
        println!("[{id}] tokens in scan window: {tokens}");
    }
    if let Some(cost) = usage.cost_today_usd {
        println!(
            "[{id}] cost in scan window: ${cost:.2}{}",
            if usage.cost_is_estimated { " (estimated)" } else { "" }
        );
    }
    if let Some(err) = &usage.error {
        println!("[{id}] ERROR {err}");
    }
}
