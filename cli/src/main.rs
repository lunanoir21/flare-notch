//! flare command line front end.
//!
//! In JSON mode stdout carries JSON and nothing else, because the Quickshell
//! widget parses it directly and any stray line would break it. Everything
//! diagnostic goes to stderr. `doctor` is the exception: plain text for a
//! terminal, never for a parser.

mod doctor;
mod watch;

use std::path::Path;

use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand, ValueEnum};
use flare_core::{Config, Fetch, ProviderUsage, SOURCE_LOCAL, Status, UsageProvider, accounts, config, history, paths, providers, sessions};

#[derive(Debug, Parser)]
#[command(name = "flare", version, about = "AI coding usage for Quickshell, read the way Codenotch reads it")]
struct Cli {
    #[command(subcommand)]
    command: Option<Command>,

    /// Which provider to report on: all, claude, codex, cursor, opencode,
    /// antigravity, kiro, or another login such as claude:work.
    #[arg(long, default_value = "all")]
    provider: String,

    /// Output format.
    #[arg(long, value_enum, default_value_t = Format::Json)]
    format: Format,

    /// Read now instead of waiting for each provider's own pace. A server's
    /// retry deadline still holds.
    #[arg(long, global = true)]
    refresh: bool,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Print a human-readable report of what flare can and cannot find.
    Doctor,
    /// Bring the terminal a live session runs in to the front (Hyprland).
    Focus {
        /// The session's pid, as listed under `sessions`.
        pid: u32,
    },
    /// Stay running and send desktop notifications, as `[notify]` sets them.
    Watch,
    /// Tokens (or credits) and replies per hour over the last eight days, as JSON.
    Activity,
    /// Read or change the config file.
    Config {
        #[command(subcommand)]
        action: ConfigAction,
    },
}

#[derive(Debug, Subcommand)]
enum ConfigAction {
    /// Print the config file's path.
    Path,
    /// Write a commented config file holding every default.
    Init {
        /// Replace a config file that already exists.
        #[arg(long)]
        force: bool,
    },
    /// Print the effective config (the file over the defaults) as JSON.
    Get,
    /// Set one key and print the effective config, e.g. `flare config set notch.style aura`.
    Set {
        key: String,
        #[arg(allow_hyphen_values = true)]
        value: String,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
enum Format {
    Json,
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let (config, config_problem) = Config::load();
    if let Some(problem) = &config_problem {
        eprintln!("warning: config: {problem}");
    }
    let ctx = Fetch { now: paths::now_secs(), force: cli.refresh };
    let one = (cli.provider != "all").then_some(cli.provider.as_str());
    let named = |fallback: &str| -> Result<Box<dyn UsageProvider>> {
        let id = one.unwrap_or(fallback);
        providers::by_id(id, &config).with_context(|| format!("unknown provider or login: {id}"))
    };

    match cli.command {
        Some(Command::Doctor) => {
            doctor::run(&config, config_problem.as_deref(), &ctx);
            return Ok(());
        }
        Some(Command::Config { action }) => return run_config(action, &config, config_problem),
        Some(Command::Watch) => return watch::run(config),
        Some(Command::Activity) => {
            let cutoff = ctx.now - 8 * 86_400;
            let activity = named("claude")?.activity(cutoff);
            let json = match activity {
                Some(activity) => serde_json::to_string(&activity)?,
                None => serde_json::json!({ "unit": "tokens", "hours": null }).to_string(),
            };
            println!("{json}");
            return Ok(());
        }
        Some(Command::Focus { pid }) => return sessions::focus(named("claude")?.as_ref(), pid),
        None => {}
    }

    let json = match one {
        None => {
            let mut all = fetch_all(&providers::for_widget(&config), &ctx);
            for usage in &mut all {
                usage.hidden = !config.enabled(&usage.provider);
            }
            render(cli.format, &all)
        }
        Some(_) => render(cli.format, &fetch(named("claude")?.as_ref(), &ctx)),
    }?;
    println!("{json}");
    Ok(())
}

/// Every provider at once, so one slow endpoint does not hold up the rest.
fn fetch_all(list: &[Box<dyn UsageProvider>], ctx: &Fetch) -> Vec<ProviderUsage> {
    std::thread::scope(|scope| {
        let handles: Vec<_> = list
            .iter()
            .map(|provider| scope.spawn(move || fetch(provider.as_ref(), ctx)))
            .collect();
        handles
            .into_iter()
            .zip(list)
            .map(|(handle, provider)| {
                handle.join().unwrap_or_else(|_| failed(provider.id(), "the provider crashed".into()))
            })
            .collect()
    })
}

fn fetch(provider: &dyn UsageProvider, ctx: &Fetch) -> ProviderUsage {
    let mut usage = provider
        .fetch(ctx)
        .unwrap_or_else(|err| failed(provider.id(), format!("{err:#}")));
    if usage.status != Status::Absent {
        usage.sessions = sessions::live(provider);
        usage.history = history::record(&usage, ctx.now);
        usage.session_log = provider
            .session_log(ctx.now)
            .unwrap_or_else(|| sessions::record(provider.id(), &usage.sessions, ctx.now));
    }
    usage
}

fn failed(id: &str, detail: String) -> ProviderUsage {
    let mut usage = ProviderUsage::new(id, SOURCE_LOCAL).with_error(detail);
    usage.status = Status::Error;
    usage
}

fn run_config(action: ConfigAction, loaded: &Config, problem: Option<String>) -> Result<()> {
    let path = Config::path()?;
    match action {
        ConfigAction::Path => println!("{}", path.display()),
        ConfigAction::Init { force } => {
            if path.exists() && !force {
                bail!("{} already exists; pass --force to replace it", path.display());
            }
            config::write_atomic(&path, config::TEMPLATE)?;
            eprintln!("wrote {}", path.display());
        }
        ConfigAction::Get => print_effective(&path, loaded, problem.as_deref())?,
        ConfigAction::Set { key, value } => {
            config::set_value(&path, &key, &value)?;
            let (reloaded, problem) = Config::load_from(&path);
            print_effective(&path, &reloaded, problem.as_deref())?;
        }
    }
    Ok(())
}

fn print_effective(path: &Path, config: &Config, problem: Option<&str>) -> Result<()> {
    let body = serde_json::json!({
        "path": path,
        "problem": problem,
        "order": config.provider_order(),
        "accounts": accounts::all(config),
        "config": config,
    });
    println!("{}", serde_json::to_string_pretty(&body)?);
    Ok(())
}

fn render<T: serde::Serialize>(format: Format, value: &T) -> Result<String> {
    match format {
        Format::Json => serde_json::to_string_pretty(value).context("failed to serialize usage snapshot"),
    }
}
