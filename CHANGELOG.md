# Changelog

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
