#!/usr/bin/env bash
#
# One-line installer for Vee — the app and the `vee` CLI.
#
#   curl -fsSL https://vee.navbytes.io/install.sh | bash
#
# Installs the latest release (or $VEE_VERSION) into /Applications and links the
# CLI onto your PATH. Homebrew does the same thing and handles upgrades for you
# (`brew install --cask vee`); this exists for machines without Homebrew.
#
# Environment:
#   VEE_VERSION   release to install, e.g. v0.2.0 (default: latest)
#   VEE_APP_DIR   where Vee.app goes (default: /Applications)
#   VEE_BIN_DIR   where the `vee` symlink goes (default: the first writable of
#                 ~/.local/bin, /usr/local/bin)
set -euo pipefail

REPO="navbytes/vee"
APP_DIR="${VEE_APP_DIR:-/Applications}"

info() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

# ── Preflight ────────────────────────────────────────────────────────────────
# Fail with the actual reason rather than letting an unpackable download or a
# crash-on-launch be the first sign something is wrong.

[ "$(uname -s)" = "Darwin" ] || die "Vee is macOS only (found $(uname -s))."

arch="$(uname -m)"
[ "$arch" = "arm64" ] || die "Vee requires Apple Silicon; this machine is $arch. There is no Intel build."

major="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$major" -lt 26 ]; then
  die "Vee requires macOS 26 or later (found $(sw_vers -productVersion))."
fi

for tool in curl ditto; do
  command -v "$tool" >/dev/null || die "'$tool' is required but not installed."
done

# ── Resolve the release ──────────────────────────────────────────────────────

version="${VEE_VERSION:-}"
if [ -z "$version" ]; then
  info "Looking up the latest release…"
  version="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$version" ] || die "Could not determine the latest release. Set VEE_VERSION=vX.Y.Z to pin one."
fi
url="https://github.com/${REPO}/releases/download/${version}/Vee.zip"

# ── Download ─────────────────────────────────────────────────────────────────

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

info "Downloading Vee ${version}…"
curl -fsSL --retry 3 -o "$tmp/Vee.zip" "$url" \
  || die "Download failed: $url"

info "Unpacking…"
ditto -x -k "$tmp/Vee.zip" "$tmp/unpacked" || die "Could not unpack Vee.zip."
[ -d "$tmp/unpacked/Vee.app" ] || die "Vee.app was not in the downloaded archive."

# ── Install the app ──────────────────────────────────────────────────────────
# Replace rather than merge: a stale file left from an older build inside the
# bundle can break code signing in ways that surface much later.

target="$APP_DIR/Vee.app"
if [ -e "$target" ]; then
  info "Replacing the existing ${target}…"
  if [ -w "$APP_DIR" ]; then rm -rf "$target"; else sudo rm -rf "$target"; fi
fi

info "Installing to ${target}…"
if [ -w "$APP_DIR" ]; then
  ditto "$tmp/unpacked/Vee.app" "$target"
else
  warn "$APP_DIR is not writable — asking for your password."
  sudo ditto "$tmp/unpacked/Vee.app" "$target"
fi

# Releases are notarized and stapled, so Gatekeeper is satisfied offline. The
# quarantine flag curl attaches is still cleared here so the first launch does
# not show the "downloaded from the internet" prompt.
xattr -dr com.apple.quarantine "$target" 2>/dev/null || true

# ── Link the CLI ─────────────────────────────────────────────────────────────
# The app bundle's executable is also the CLI, so the symlink costs nothing and
# stays correct across upgrades.

bin_dir="${VEE_BIN_DIR:-}"
if [ -z "$bin_dir" ]; then
  for candidate in "$HOME/.local/bin" "/usr/local/bin"; do
    if [ -d "$candidate" ] && [ -w "$candidate" ]; then bin_dir="$candidate"; break; fi
  done
  # Nothing suitable exists yet — ~/.local/bin needs no sudo, so prefer it.
  [ -n "$bin_dir" ] || { bin_dir="$HOME/.local/bin"; mkdir -p "$bin_dir"; }
fi

mkdir -p "$bin_dir" 2>/dev/null || true
if [ -w "$bin_dir" ]; then
  ln -sf "$target/Contents/MacOS/Vee" "$bin_dir/vee"
else
  sudo mkdir -p "$bin_dir"
  sudo ln -sf "$target/Contents/MacOS/Vee" "$bin_dir/vee"
fi
info "Linked the CLI at $bin_dir/vee"

case ":${PATH}:" in
  *":${bin_dir}:"*) ;;
  *) warn "${bin_dir} is not on your PATH. Add it:"
     # shellcheck disable=SC2016  # $PATH must stay literal in the printed hint
     printf '\n  export PATH="%s:$PATH"\n\n' "$bin_dir" ;;
esac

# ── Done ─────────────────────────────────────────────────────────────────────

info "Installed Vee ${version}."
echo
echo "  open -a Vee      launch the menu-bar app"
echo "  vee --help       the CLI"
echo
echo "Upgrade later by re-running this script, or install via Homebrew"
echo "(brew install --cask vee) to get upgrades through brew."
