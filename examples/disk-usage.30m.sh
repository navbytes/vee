#!/usr/bin/env bash
#
# disk-usage.30m.sh — shows free space on your startup volume in the menu bar,
# color-coded, and re-checks every 30 minutes (the ".30m" in the filename).
#
# This plugin reads system state by shelling out to `df`, so it honestly
# declares that with <vee.exec>df</vee.exec>. That is the only capability it
# needs: no network, no secrets, no files it writes. Vee will show an "exec:
# df" badge in the trust summary. The declaration is ADVISORY — Vee does not
# stop the plugin from doing more; it just surfaces what a well-behaved plugin
# claims. Declare honestly.
#
# ---------------------------------------------------------------------------
# Metadata
# ---------------------------------------------------------------------------
# <xbar.title>Disk Usage</xbar.title>
# <xbar.version>1.0</xbar.version>
# <xbar.author>Naveen Kumar</xbar.author>
# <xbar.author.github>navbytes</xbar.author.github>
# <xbar.desc>Free space on the startup volume, color-coded, with an SF Symbol.</xbar.desc>
# <xbar.dependencies>bash,df</xbar.dependencies>
#
# Trust declarations (advisory, never enforced):
# <vee.capabilities>exec</vee.capabilities>
# <vee.exec>df</vee.exec>

set -euo pipefail

# ---------------------------------------------------------------------------
# Defensive check: make sure the tool we depend on actually exists. A plugin
# should degrade gracefully rather than error out with a confusing message.
# ---------------------------------------------------------------------------
if ! command -v df >/dev/null 2>&1; then
  echo "Disk ⚠️ | sfimage=externaldrive.badge.exclamationmark color=red"
  echo "---"
  echo "\`df\` not found on PATH"
  exit 0
fi

# ---------------------------------------------------------------------------
# Read disk usage for the root volume "/".
#   df -Pk /   -> POSIX output, 1K blocks (portable, stable columns).
# We parse the data row (NR==2): total, used, avail (KB), and the % used.
# ---------------------------------------------------------------------------
read -r avail_kb capacity <<EOF
$(df -Pk / | awk 'NR==2 { gsub("%","",$5); print $4, $5 }')
EOF

# Convert available kilobytes to a human-friendly GB figure (integer math to
# avoid depending on `bc`).
avail_gb=$(( avail_kb / 1024 / 1024 ))
used_pct=${capacity:-0}
free_pct=$(( 100 - used_pct ))

# ---------------------------------------------------------------------------
# Color-code: green when there's plenty free, orange when getting tight, red
# when low. This is the kind of at-a-glance signal the menu bar is great for.
# ---------------------------------------------------------------------------
if   [ "$free_pct" -le 10 ]; then color="red"
elif [ "$free_pct" -le 25 ]; then color="orange"
else                              color="green"
fi

# The menu-bar title: an SF Symbol + the free space, tinted by how full we are.
echo "${avail_gb}GB | sfimage=internaldrive color=${color}"

# ---------------------------------------------------------------------------
# Dropdown: the details.
# ---------------------------------------------------------------------------
echo "---"
echo "Startup volume (/) | color=gray"
echo "Free: ${avail_gb} GB (${free_pct}%)"
echo "Used: ${used_pct}%"
echo "---"
# `terminal=false` runs the command in the background (no Terminal window).
# Here we open Disk Utility so the user can dig in.
echo "Open Disk Utility | bash=/usr/bin/open param1=-a param2='Disk Utility' terminal=false"
echo "Refresh | refresh=true"
