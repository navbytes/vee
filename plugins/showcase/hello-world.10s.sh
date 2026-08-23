#!/usr/bin/env bash
#
# hello-world.10s.sh — the smallest useful Vee plugin, built to teach the format.
#
# The ".10s" in the filename tells Vee to re-run this script every 10 seconds.
# Change it to .5s, .1m, .30m, .1h, etc. to change the refresh interval — the
# interval lives in the filename, not in the script.
#
# This plugin declares NO capabilities: it touches no network, no files, no
# secrets, and runs no external tools. Vee will show it as having nothing to
# declare — the most trustworthy kind of plugin.
#
# ---------------------------------------------------------------------------
# Metadata headers (optional). These live in comments and are language-agnostic;
# Vee scans for them regardless of the comment syntax. They power the About box
# and the plugin manager.
# ---------------------------------------------------------------------------
# <xbar.title>Hello World</xbar.title>
# <xbar.version>1.0</xbar.version>
# <xbar.author>Naveen Kumar</xbar.author>
# <xbar.author.github>navbytes</xbar.author.github>
# <xbar.desc>Minimal example that teaches the Vee/xbar output format.</xbar.desc>
# <xbar.dependencies>bash</xbar.dependencies>
#
# This plugin needs no capabilities, so it declares none. (An empty declaration
# is itself a signal: Vee shows "nothing declared".)
# <vee.capabilities></vee.capabilities>

# ---------------------------------------------------------------------------
# THE OUTPUT
#
# Everything a plugin prints to stdout is its output. Vee splits it into two
# parts on the first line that is exactly three dashes ("---"):
#
#   * Lines BEFORE "---"  -> the menu-bar item(s) (the "title").
#   * Lines AFTER "---"   -> the dropdown menu shown when you click it.
# ---------------------------------------------------------------------------

# The menu-bar title. `sfimage=hand.wave` renders an SF Symbol next to the text.
echo "Hello 👋 | sfimage=hand.wave"

# The separator: a line of exactly three dashes starts the dropdown.
echo "---"

# A plain, non-clickable dropdown line.
echo "This is a Vee plugin."

# `color=` accepts CSS/AppKit color names or hex (#f00, #ff0000, #ff0000ff).
echo "Refreshes every 10 seconds | color=gray"

# A clickable link. `href=` opens the URL in your browser.
echo "Learn the format | href=https://github.com/navbytes/vee"

# A submenu: prefix a line with "--" to nest it under the item above it.
echo "More examples"
echo "-- Disk usage (disk-usage.30m.sh)"
echo "-- GitHub notifications (github-notifications.5m.sh)"

# Another separator, then a "Refresh" action. `refresh=true` makes Vee re-run
# the plugin immediately when this item is clicked.
echo "---"
echo "Refresh | refresh=true"
