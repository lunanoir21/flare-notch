//! `flare watch`: a long-running process that sends desktop notifications.
//!
//! Sessions are rescanned every couple of seconds (a few small files, no
//! child processes); usage at the widget's pace but never more than once a
//! minute, and each provider still keeps its own network pace. The process
//! ends once every notification is switched off, or when whoever started it
//! goes away.

use std::time::{Duration, Instant};

use anyhow::Result;
use flare_core::config::Language;
use flare_core::notify::{Event, Tracker};
use flare_core::{Config, Fetch, paths, providers, sessions};

const SESSION_EVERY: Duration = Duration::from_secs(2);
const CONFIG_EVERY: Duration = Duration::from_secs(10);
const MIN_USAGE_EVERY_SECS: u64 = 60;

pub fn run(mut config: Config) -> Result<()> {
    let parent = std::os::unix::process::parent_id();
    let mut tracker = Tracker::default();
    let mut config_read = Instant::now();
    let mut usage_read: Option<Instant> = None;

    loop {
        if std::os::unix::process::parent_id() != parent {
            return Ok(());
        }
        if config_read.elapsed() >= CONFIG_EVERY {
            config = Config::load().0;
            config_read = Instant::now();
        }
        if !config.notify.any() {
            return Ok(());
        }
        let turkish = turkish(&config);

        if config.enabled("claude") {
            let found = sessions::scan("claude");
            for event in tracker.sessions("claude", &found, &config.notify) {
                send(event, turkish);
            }
        }

        let usage_every = Duration::from_secs(config.poll.interval_secs.max(MIN_USAGE_EVERY_SECS));
        if (config.notify.limit || config.notify.reset) && usage_read.is_none_or(|at| at.elapsed() >= usage_every) {
            let ctx = Fetch { now: paths::now_secs(), force: false };
            for usage in super::fetch_all(&providers::all(&config), &ctx) {
                for event in tracker.usage(&usage, &config.notify) {
                    send(event, turkish);
                }
            }
            usage_read = Some(Instant::now());
        }

        std::thread::sleep(SESSION_EVERY);
    }
}

fn turkish(config: &Config) -> bool {
    match config.ui.language {
        Language::Tr => true,
        Language::En => false,
        Language::Auto => ["LC_ALL", "LC_MESSAGES", "LANG"]
            .iter()
            .find_map(|key| std::env::var(key).ok().filter(|v| !v.is_empty()))
            .is_some_and(|locale| locale.to_lowercase().starts_with("tr")),
    }
}

fn name(provider: &str) -> &str {
    match provider {
        "claude" => "Claude",
        "codex" => "Codex",
        "cursor" => "Cursor",
        "opencode" => "OpenCode",
        other => other,
    }
}

/// Each notification on its own thread: one with an action waits for the
/// user, and must not hold up the loop.
fn send(event: Event, turkish: bool) {
    std::thread::spawn(move || {
        let (title, body, urgency, jump) = match &event {
            Event::Waiting { provider, pid, name: session, waiting_for } => {
                if !sessions::reachable(*pid) {
                    return;
                }
                let title = if turkish {
                    format!("{} seni bekliyor", name(provider))
                } else {
                    format!("{} is waiting on you", name(provider))
                };
                let body = match waiting_for {
                    Some(what) if !turkish => format!("{session} · {what}"),
                    _ => session.clone(),
                };
                (title, body, "normal", Some((provider.clone(), *pid)))
            }
            Event::Limit { provider, window, used } => {
                let percent = (used * 100.0).floor();
                let body = if turkish { format!("%{percent} kullanıldı") } else { format!("{percent}% used") };
                (format!("{} · {window}", name(provider)), body, "critical", None)
            }
            Event::Reset { provider, window } => {
                let body = if turkish { "Limit yenilendi" } else { "Limit renewed" };
                (format!("{} · {window}", name(provider)), body.to_string(), "low", None)
            }
        };
        let mut command = std::process::Command::new("notify-send");
        command.args(["--app-name", "flare", "--urgency", urgency]);
        if jump.is_some() {
            command.args(["--action", if turkish { "focus=Aç" } else { "focus=Open" }]);
        }
        command.args([title.as_str(), body.as_str()]);
        let output = match command.output() {
            Ok(output) => output,
            Err(err) => {
                eprintln!("could not run notify-send: {err}");
                return;
            }
        };
        if let Some((provider, pid)) = jump {
            if String::from_utf8_lossy(&output.stdout).trim() == "focus" {
                if let Err(err) = sessions::focus(&provider, pid) {
                    eprintln!("{err:#}");
                }
            }
        }
    });
}
