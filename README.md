# flare

A usage notch for Quickshell on Hyprland: how much of your Claude Code, Codex,
Cursor and OpenCode allowance is left, welded to the edge of the screen.

[Türkçe README](README.tr.md)

## Three looks

| Style | What it is |
|---|---|
| **classic** | Codenotch's notch. A black body with inverse rounded corners on the left or right edge, one ring per provider. Hover a ring for the detail card; click it to open that provider's usage page. |
| **aura** | One provider at a time, tinted with its colour. The others wait below as a logo and a number. Tap one, or bind Super + ← / → to the `next` / `prev` IPC calls (see Keybinds). |
| **compact** | A thin strip on the top or bottom edge. One tap grows it into a panel with a row per provider; another tap closes it. |

Rings go green under 50 %, yellow under 70 %, orange above. A reading flare could
not refresh is dimmed, never invented.

Right-click the widget for its settings page. Drag it along its edge to move it.

## Where the numbers come from

`data.mode` picks one of two ways.

**official** (default) reads each provider the way Codenotch does:

| Provider | Source |
|---|---|
| Claude Code | `GET api.anthropic.com/api/oauth/usage` with the token Claude Code keeps in `~/.claude/.credentials.json`. An expired token is never sent; it is renewed shortly before expiry by running `claude -p`. A 429 backs off from one minute to fifteen, and the deadline survives restarts. Where the endpoint cannot answer, a fresh status line capture stands in. |
| Codex | `GET chatgpt.com/backend-api/wham/usage` with the session in `~/.codex/auth.json`, falling back to the limits Codex wrote into its newest rollout log. |
| Cursor | `GET cursor.com/api/usage-summary` with the editor's own session from `~/.config/Cursor/User/globalStorage/state.vscdb`. |
| OpenCode | Its local database. OpenCode runs on your own API keys, so it shows tokens today rather than a limit. |

**local** never opens a network connection. Claude comes from the status line
capture (below), Codex from its rollout logs, OpenCode from its database. Cursor
keeps no usage on disk, so it shows nothing in this mode.

Credentials are read, never written, and never printed: `flare doctor` describes a
token by its length. Network reads keep their own pace — Claude every minute, Codex
and Cursor every five — however often the widget refreshes.

## Install

Requires Rust 1.85+, Quickshell 0.3+ and Qt 6.6+.

```sh
git clone https://github.com/lunanoir21/quickshell-flare
cd quickshell-flare
cargo build --release
./target/release/flare doctor
```

The widget finds the binary it was built next to. To install it elsewhere, put it on
`PATH` or in `~/.local/bin`, or set `flare.binary_path`.

### Run it on its own

```sh
quickshell -p ui
```

### Or inside your shell

```qml
import "path/to/quickshell-flare/ui" as Flare

ShellRoot {
    Flare.FlareHost {}
}
```

### Claude in local mode: the status line capture

Claude Code keeps its 5-hour and weekly percentages in memory and hands them only to
its status line command. `hooks/claude-statusline-capture.sh` writes that payload to
`~/.local/state/flare/` and passes it on unchanged. Put it in front of whatever you
already use, in `~/.claude/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "/path/to/quickshell-flare/hooks/claude-statusline-capture.sh npx -y @owloops/claude-powerline@latest"
}
```

Official mode does not need it, but uses a fresh capture when the endpoint is down.

## Configuration

Everything lives in `~/.config/flare/config.toml`. The settings page writes the same
file, through the same command a terminal uses:

```sh
flare config init                      # a commented file with every default
flare config set notch.style aura
flare config set notch.edge right
flare config set providers.order claude,cursor,codex,opencode
flare config set aura.claude "#E07A5F"
flare config set data.mode local
flare config get                       # the effective config, as JSON
```

`set` refuses unknown keys and values a key cannot hold, and keeps the file's
comments. The widget picks up a saved change within a second.

| Key | Values |
|---|---|
| `data.mode` | `official`, `local` |
| `notch.style` | `classic`, `aura`, `compact` |
| `notch.edge` | `left`, `right` |
| `notch.offset` | pixels from the centre, along the edge |
| `notch.scale` | `0.5` to `2.0` |
| `notch.screen` | output name, or empty for every screen |
| `compact.edge` | `top`, `bottom` |
| `compact.offset` | pixels from the centre, along the edge |
| `compact.open_on` | `click`, `hover` |
| `providers.claude` … `providers.opencode` | `true`, `false` |
| `providers.order` | the order cells are drawn and aura steps through |
| `aura.claude` … `aura.opencode` | `#RRGGBB` |
| `poll.interval_secs` | widget refresh, at least 5 |
| `scan.window_days` | days of logs counted toward token totals |

## Keybinds

flare listens on Quickshell IPC as `flare`:

| Call | Does |
|---|---|
| `next`, `prev` | step aura to the next or previous provider |
| `toggle` | open or close the compact panel |
| `style classic\|aura\|compact` | switch style |
| `settings` | open or close the settings page |
| `refresh` | read now |

For Hyprland, with flare inside the shell at `~/.config/quickshell/shell.qml`:

```ini
bind = SUPER, right, exec, qs ipc call flare next
bind = SUPER, left,  exec, qs ipc call flare prev
bind = SUPER, U,     exec, qs ipc call flare toggle
```

Add `-p /path/to/shell.qml` after `qs` when your shell lives elsewhere.

## Credit where it is due

flare exists because of [Codenotch](https://github.com/vinzdg/codenotch) by Vinz. The
notch itself — its shape, its rings and colours, the hover card, the rule that a
reading is never invented — is Codenotch's design, and the way flare reads each
provider follows Codenotch's providers. Codenotch also showed what it takes to bring
the idea to a desktop that is not a Mac, which is the whole of what flare tries to do
for Hyprland. No Swift code was copied; the Rust here was written against the
behaviour Codenotch documents.

[Codenotch for Windows](https://github.com/Im-Midi/codenotch-windows) by Im-Midi wrote
those provider semantics down in portable Rust, which made the Linux reading of every
wire format far less of a guess.

Local mode's technique — reading what each agent already wrote to disk — comes from
[Orca](https://github.com/stablyai/orca), and the wish to see AI usage at a glance
from [CodexBar](https://github.com/steipete/CodexBar).

Provider logos are from [LobeHub Icons](https://github.com/lobehub/lobe-icons) (MIT);
see `ui/assets/logos/NOTICE.md`. The logos are trademarks of their owners.

## License

MIT — see `LICENSE`.
