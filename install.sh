#!/bin/sh
# Installs the flare binary to ~/.local/bin (or $FLARE_BIN_DIR): built from
# this checkout when cargo is available, otherwise the latest release build.
set -eu

repo="lunanoir21/quickshell-flare"
bin_dir="${FLARE_BIN_DIR:-$HOME/.local/bin}"
here=$(cd "$(dirname "$0")" && pwd)

say() { printf '%s\n' "$*" >&2; }

mkdir -p "$bin_dir"

if command -v cargo >/dev/null 2>&1 && [ -f "$here/Cargo.toml" ]; then
    say "building flare from $here"
    cargo build --release --manifest-path "$here/Cargo.toml"
    install -m 755 "$here/target/release/flare" "$bin_dir/flare"
else
    [ "$(uname -m)" = "x86_64" ] || { say "no release build for $(uname -m); install Rust and run this again"; exit 1; }
    command -v curl >/dev/null 2>&1 || { say "curl is needed to download the release build"; exit 1; }
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    say "downloading the latest release build"
    curl -fsSL "https://github.com/$repo/releases/latest/download/flare-x86_64-linux.tar.gz" -o "$tmp/flare.tar.gz"
    tar -xzf "$tmp/flare.tar.gz" -C "$tmp"
    install -m 755 "$tmp/flare" "$bin_dir/flare"
fi

say "installed $bin_dir/flare"

# An app launcher entry named flare that opens the settings page.
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
mkdir -p "$data_dir/applications" "$data_dir/icons/hicolor/scalable/apps"
sed "s|@UI_DIR@|$here/ui|" "$here/packaging/flare-settings.sh" > "$bin_dir/flare-settings"
chmod 755 "$bin_dir/flare-settings"
sed "s|@BIN_DIR@|$bin_dir|" "$here/packaging/flare.desktop" > "$data_dir/applications/flare.desktop"
install -m 644 "$here/docs/assets/flare.svg" "$data_dir/icons/hicolor/scalable/apps/flare.svg"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$data_dir/applications" 2>/dev/null || true
say "added flare to the app launcher; it opens the settings page"
case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *)
        if [ "$bin_dir" = "$HOME/.local/bin" ]; then
            say "note: $bin_dir is not on PATH; the widget still finds it there"
        else
            say "note: $bin_dir is not on PATH; run: flare config set flare.binary_path $bin_dir/flare"
        fi
        ;;
esac

"$bin_dir/flare" doctor || true

say ""
say "run the widget on its own:   quickshell -p $here/ui"
