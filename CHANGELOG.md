# Changelog

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
- **A website:** [lunanoir21.github.io/quickshell-flare](https://lunanoir21.github.io/quickshell-flare/),
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
