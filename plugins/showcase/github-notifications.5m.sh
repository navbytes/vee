#!/usr/bin/env bash
#
# github-notifications.5m.sh — shows your unread GitHub notification count in the
# menu bar and lists the most recent ones in the dropdown. Re-checks every 5
# minutes (the ".5m" in the filename).
#
# This is the flagship trust-model demo. It:
#   * reaches the network      -> <vee.network>api.github.com</vee.network>
#   * uses a secret token      -> <vee.secrets>GITHUB_TOKEN</vee.secrets>
#   * shells out to curl (jq)  -> <vee.exec>curl, jq</vee.exec>
#
# All three are DECLARED honestly below. Vee parses those declarations and shows
# a trust summary (a "network: api.github.com" badge, a "secrets: GITHUB_TOKEN"
# badge, etc.). The declarations are ADVISORY — Vee never enforces them; they
# exist so you can see, at a glance, what a well-behaved plugin claims to touch
# before you trust it with a token. Only run plugins you trust; read the source.
#
# ---------------------------------------------------------------------------
# Metadata + typed preferences
#
# <xbar.var> declares a preference. Vee renders a settings form for it; because
# this variable's name contains "token", Vee treats it as a SECRET and stores
# the value in the macOS Keychain (never in plain text). The plugin reads it as
# an environment variable at run time.
# ---------------------------------------------------------------------------
# <xbar.title>GitHub Notifications</xbar.title>
# <xbar.version>1.0</xbar.version>
# <xbar.author>Naveen Kumar</xbar.author>
# <xbar.author.github>navbytes</xbar.author.github>
# <xbar.desc>Unread GitHub notification count, with the latest in the dropdown.</xbar.desc>
# <xbar.dependencies>bash,curl,jq</xbar.dependencies>
# <xbar.abouturl>https://docs.github.com/en/rest/activity/notifications</xbar.abouturl>
#
# <xbar.var>string(GITHUB_TOKEN=""): A GitHub personal access token with the "notifications" scope.</xbar.var>
#
# Trust declarations (advisory, never enforced):
# <vee.capabilities>network,secrets,exec</vee.capabilities>
# <vee.network>api.github.com</vee.network>
# <vee.secrets>GITHUB_TOKEN</vee.secrets>
# <vee.exec>curl, jq</vee.exec>

set -euo pipefail

ICON="bell.badge"

# ---------------------------------------------------------------------------
# Degrade gracefully when the token is not set. A good plugin never breaks the
# menu bar — it tells you what to do. The token is provided by Vee via the
# GITHUB_TOKEN environment variable (from the <xbar.var> above, stored in the
# Keychain). ${GITHUB_TOKEN:-} avoids "unbound variable" under `set -u`.
# ---------------------------------------------------------------------------
if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "GitHub | sfimage=${ICON} color=gray"
  echo "---"
  echo "No token set | color=gray"
  echo "Add a GITHUB_TOKEN in this plugin's preferences"
  echo "Create a token… | href=https://github.com/settings/tokens"
  exit 0
fi

# Defensive tool checks — same idea as the token check.
for tool in curl jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "GitHub ⚠️ | sfimage=${ICON} color=red"
    echo "---"
    echo "\`$tool\` not found on PATH"
    exit 0
  fi
done

# ---------------------------------------------------------------------------
# Fetch unread notifications from the GitHub REST API. We only ever contact
# api.github.com — exactly the host declared in <vee.network> above.
#
# `--fail`   -> curl returns non-zero on HTTP errors (e.g. 401 bad token).
# `--silent` -> no progress meter polluting stdout.
# We keep the request read-only (GET) and short-timeout so a network hiccup
# doesn't hang the menu.
# ---------------------------------------------------------------------------
response=$(
  curl --silent --fail --max-time 15 \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/notifications" 2>/dev/null
) || {
  # Network error or a bad/expired token (HTTP 4xx/5xx).
  echo "GitHub ⚠️ | sfimage=${ICON} color=red"
  echo "---"
  echo "Couldn't reach the GitHub API"
  echo "Check your token and network"
  echo "Token settings | href=https://github.com/settings/tokens"
  exit 0
}

count=$(printf '%s' "$response" | jq 'length')

# ---------------------------------------------------------------------------
# Menu-bar title: gray when zero, blue when you have unread notifications.
# ---------------------------------------------------------------------------
if [ "${count:-0}" -gt 0 ]; then
  echo "${count} | sfimage=${ICON} color=#0a84ff"
else
  echo "0 | sfimage=bell color=gray"
fi

# ---------------------------------------------------------------------------
# Dropdown: the notifications themselves, each a clickable link.
# ---------------------------------------------------------------------------
echo "---"

if [ "${count:-0}" -eq 0 ]; then
  echo "You're all caught up 🎉 | color=gray"
else
  echo "Unread (${count}) | color=gray"
  # Turn each notification into a "Title | href=<url>" line. The REST payload
  # gives an API URL for the subject; we convert it to a web URL so clicking
  # opens the issue/PR in the browser. jq does the transform safely.
  printf '%s' "$response" \
    | jq -r '.[:15][]
        | (.subject.title) as $t
        | (.subject.url // "" | sub("api\\.github\\.com/repos"; "github.com")
                              | sub("/pulls/"; "/pull/")) as $u
        | "\($t) | href=\($u)"'
fi

echo "---"
echo "Open all notifications | href=https://github.com/notifications"
echo "Refresh | refresh=true"
