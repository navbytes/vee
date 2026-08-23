#!/usr/bin/env bash
#
# One-line installer for Vee — the app and the `vee` CLI.
#
#   curl -fsSL https://vee.navbytes.io/install.sh | bash
#
# Installs the latest release into /Applications and links the CLI onto your
# PATH. Homebrew does the same thing and handles upgrades for you
# (`brew install --cask vee`); this exists for machines without Homebrew.
#
# Options — pass them after `bash -s --`, which is the form that survives a
# pipe. `VAR=x curl ... | bash` sets VAR for *curl*, not for the bash reading
# the script, so the setting is silently ignored:
#
#   curl -fsSL https://vee.navbytes.io/install.sh | bash -s -- --app-dir ~/Applications
#
#   --app-dir DIR   where Vee.app goes (default: /Applications)
#   --bin-dir DIR   where the `vee` symlink goes (default: the first writable
#                   of ~/.local/bin, /usr/local/bin)
#   --version TAG   release to install, e.g. v0.2.0 (default: latest)
#
# The matching environment variables (VEE_APP_DIR, VEE_BIN_DIR, VEE_VERSION)
# also work when they genuinely reach this script — exported, or set on the
# `bash` itself. A flag wins over the environment.
set -euo pipefail

REPO="navbytes/vee"

info() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Install Vee — the menu-bar app and the `vee` CLI.

  curl -fsSL https://vee.navbytes.io/install.sh | bash
  curl -fsSL https://vee.navbytes.io/install.sh | bash -s -- --app-dir ~/Applications

Options:
  --app-dir DIR   where Vee.app goes (default: /Applications)
  --bin-dir DIR   where the `vee` symlink goes (default: the first writable of
                  ~/.local/bin, /usr/local/bin)
  --version TAG   release to install, e.g. v0.2.0 (default: latest)
  -h, --help      show this and exit
USAGE
}

# Flags beat the environment. Both are supported because `VAR=x curl ... | bash`
# looks like it should work and does not: the assignment applies to curl, and
# the bash reading the script on stdin never sees it.
app_dir="${VEE_APP_DIR:-}"
bin_dir_opt="${VEE_BIN_DIR:-}"
version="${VEE_VERSION:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --app-dir) [ $# -ge 2 ] || die "--app-dir needs a directory"; app_dir="$2"; shift 2 ;;
    --bin-dir) [ $# -ge 2 ] || die "--bin-dir needs a directory"; bin_dir_opt="$2"; shift 2 ;;
    --version) [ $# -ge 2 ] || die "--version needs a tag"; version="$2"; shift 2 ;;
    --app-dir=*) app_dir="${1#*=}"; shift ;;
    --bin-dir=*) bin_dir_opt="${1#*=}"; shift ;;
    --version=*) version="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option '$1' (try --help)" ;;
  esac
done

APP_DIR="${app_dir:-/Applications}"

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

# Try the operation and escalate only when it actually fails, rather than
# predicting with `[ -w ]`. That test is wrong in both directions here: it is
# false for a directory that does not exist yet (so `--app-dir ~/Applications`
# on a Mac without that folder would ask for a password instead of just
# creating it), and it is true for a directory macOS then refuses to let us
# write to under App Management/TCC.
escalated=false
run_maybe_sudo() {
  first_error="$("$@" 2>&1 >/dev/null)" && return 0
  if [ "$escalated" = false ]; then
    warn "Need administrator rights — asking for your password."
    escalated=true
  fi
  if sudo "$@"; then return 0; fi
  # Both attempts failed, so the cause is not permissions. Show what the
  # unprivileged attempt actually said rather than leaving a bare exit code.
  [ -n "$first_error" ] && warn "$first_error"
  die "Could not write to $APP_DIR."
}

[ -d "$APP_DIR" ] || run_maybe_sudo mkdir -p "$APP_DIR"

target="$APP_DIR/Vee.app"
if [ -e "$target" ]; then
  info "Replacing the existing ${target}…"
  run_maybe_sudo rm -rf "$target"
fi

info "Installing to ${target}…"
run_maybe_sudo ditto "$tmp/unpacked/Vee.app" "$target"

# Releases are notarized and stapled, so Gatekeeper is satisfied offline. The
# quarantine flag curl attaches is still cleared here so the first launch does
# not show the "downloaded from the internet" prompt.
xattr -dr com.apple.quarantine "$target" 2>/dev/null || true

# ── Link the CLI ─────────────────────────────────────────────────────────────
# The app bundle's executable is also the CLI, so the symlink costs nothing and
# stays correct across upgrades.

bin_dir="$bin_dir_opt"
if [ -z "$bin_dir" ]; then
  for candidate in "$HOME/.local/bin" "/usr/local/bin"; do
    if [ -d "$candidate" ]; then bin_dir="$candidate"; break; fi
  done
  # Nothing exists yet — ~/.local/bin needs no sudo, so prefer it.
  [ -n "$bin_dir" ] || bin_dir="$HOME/.local/bin"
fi

[ -d "$bin_dir" ] || run_maybe_sudo mkdir -p "$bin_dir"
run_maybe_sudo ln -sf "$target/Contents/MacOS/Vee" "$bin_dir/vee"
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
