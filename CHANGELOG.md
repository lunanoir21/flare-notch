# Changelog

## Unreleased

**`install.sh` no longer downloads a moving target:** the release-build
fallback used to fetch `releases/latest`, so a pinned checkout (an Omarchy
wrapper vendoring a fixed commit, say) could still end up installing a
different, newer binary than the one that was reviewed — its checksum came
from that same mutable release, so it verified against itself rather than
against anything the checkout actually pinned. It now downloads the release
matching the checkout's own `Cargo.toml` version, and a new `FLARE_SHA256`
lets a caller pin the expected digest itself instead of trusting whatever
`.sha256` the release page publishes at install time.

**Open sessions for OpenCode:** the live sessions list only ever worked for
Claude Code, the one CLI that keeps a per-process record
(`sessions/<pid>.json`) on disk. OpenCode keeps no such record, so flare now
finds its running `opencode` processes itself and names each one after the
session its working directory last touched in `opencode.db`. Background
`opencode serve` processes are not sessions and stay out of the list; with no
busy/waiting signal to read, every match shows as idle rather than guessing.

**Proactive audit ahead of an Omarchy marketplace submission** — Before
submitting to the Omarchy marketplace, everything flare takes from the
outside world was re-read against a hostile/malformed-input lens: every
provider's log and session files, HTTP replies, the config file, process
output. No changes were needed there — the existing bounds (line/file size
caps, no symlink following, parameterized queries, whitelisted config keys,
credentials never logged) already held. The one thing the pass did change:
session names, project names, "waiting for" text and provider error notes
are strings a provider's own session files hand flare, so the widget now
renders all of them as `Text.PlainText` instead of Qt Quick's default
auto-detected rich text — no visual change for the normal case, just no
chance of a string like a project folder name being read as markup.

## 1.0.0

flare is stable. From here on the config keys, the IPC calls and the JSON
`flare` prints keep their meaning; new ones may be added, none will change
under you.

- **More than one login:** two Claude Code or Codex logins are two rings.
  `~/.claude-<name>` and `~/.codex-<name>` are found on their own, anything else
  goes in `[[account]]`, and each login is read, renewed and reported on its
  own, with its initial on its ring.
- **Documentation:** a full reference on the site: how flare works, what it
  reads and what it sends, what it costs to run, and every setting, IPC call
  and command.
- **In your app launcher:** `install.sh` adds a **flare** entry that opens the
  settings page, and `openSettings` does the same over IPC without closing a
  page that is already open.
- **Fixed:** the white theme lost Cursor's, OpenCode's and Antigravity's logos;
  the usage panel reopened where it was left instead of at the top; a long
  pace line ran out of its card; two logins' session lists in the compact
  panel did not say whose they were.
- A logo of its own, and new screenshots, drawn from a made-up world with
  `tools/shots/shots.sh` so they never show anyone's real usage.

## 0.3.0

- **Antigravity and Kiro:** two more providers. Antigravity reads each model
  group's quota from its own status line capture (`hooks/agy-statusline-capture.sh`)
  and today's tokens and models from its conversation databases; Kiro reads the
  month's credits from AWS, or from its session files alone in `local` mode.
- **The usage panel, redone:** a deck of provider cards across the top — step
  through with the arrows — and, for the one picked, its limits, how the
  longest one filled, the last seven days, the hours of the day, the models
  that took the most and the week's sessions.
- **Sessions from a provider's own history:** OpenCode, Antigravity and Kiro
  now list closed sessions on the timeline too, not just ones still running.
- **`usage.all_providers`:** list, and read, providers switched off in the
  widget in the usage panel too.
- A provider that meters in credits (Kiro) shows credits, not tokens,
  throughout the panel and its cards.

## 0.2.0

- **The usage panel:** an hour-by-hour heatmap of the week, token counts read
  straight from a provider's own logs (each reply counted once), busiest hours,
  quietest day and today's sessions on a timeline. Open it from the arrow on a
  provider's hover card, or `qs ipc call flare usage <provider>`.
- **Notifications:** `flare watch` runs in the background, only while `[notify]`
  has something switched on, and tells you when a session starts waiting on you,
  a limit reaches its threshold, or a limit you had been using resets.
- **`notch.label`:** show the time left under a ring instead of (or beside) the
  percentage.
- **Session log:** flare now remembers a session for a week after it closes, so
  the usage panel's timeline has something to draw for earlier today.
- **Fixed:** Claude token counts were inflated, sometimes by a lot — Claude Code
  writes a reply's usage on every content-block line, and a resumed session
  copies old replies into its new log. Both are now counted once. A single very
  long line (tool output) no longer stops the rest of a log file from being read.

## 0.1.1

- **Sessions in every look:** aura opens the same hover card as classic from its
  ring, with a dot per open session under it, and compact lists the sessions under
  its provider rows.
- **Smoother compact panel:** opening the session list no longer resizes the
  panel's window on every frame, and the panel opens and closes faster.
- **`card` in aura** switches to that provider before opening its card.
- **A website:** [lunanoir21.github.io/flare-notch](https://lunanoir21.github.io/flare-notch/),
  with a working copy of the notch, the credits and this changelog, in black or
  white.
- `install.sh` suggests setting `flare.binary_path` when it installs somewhere the
  widget does not look.

## 0.1.0

The first release.

- **Providers:** Claude Code, Codex, Cursor and OpenCode, read the way Codenotch
  reads them (`data.mode = "official"`), or from disk alone (`"local"`).
- **Three looks:** classic, aura and compact, each mounted as bridge, floating or
  flush, on any edge the style allows.
- **Reveal:** always on screen, slide in on hover, or bring in with a key.
- **Hover card:** Codenotch's black card, with bars that go green, orange and red as
  a limit fills.
- **Open sessions:** the card lists the Claude Code sessions running right now,
  whether each is working or waiting on you, and clicking one brings its terminal
  to the front (Hyprland).
- **Keyboard only:** `qs ipc call flare card claude` opens the hover card without the
  pointer; `toggleSessions` folds the session list.
- **English and Turkish:** follows the locale, or `ui.language`.
- **Settings page:** every option, with a live preview; it writes the same
  `~/.config/flare/config.toml` that `flare config set` does.
- **Light on resources:** nothing is read while the widget is out of sight, and
  network reads keep their own pace however often the widget refreshes.
- `install.sh` builds from source when Rust is there, and downloads this release's
  binary otherwise.
