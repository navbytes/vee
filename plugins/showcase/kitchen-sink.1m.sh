#!/usr/bin/env bash
#
# kitchen-sink.1m.sh — one plugin, every field the JSON output format knows.
#
# Vee's structured-JSON format is the RECOMMENDED way to author new plugins:
# no `|`-param quoting, typed booleans/numbers, and clean nesting for
# submenus. A plugin opts in per run by printing a single JSON object whose
# first character is `{` and which carries `"vee":1`. This script builds one
# by hand with a heredoc (zero dependencies — no jq, no SDK) so you can read
# every field name next to the value it produces. Full reference:
# https://vee.navbytes.io/guide/json-output/
#
# This plugin declares NO capabilities that run automatically: the one
# `shell` action below only runs if you click it — it just speaks a line
# aloud with the built-in `say` command, a harmless stand-in for your real
# command.
#
# ---------------------------------------------------------------------------
# Metadata headers (optional, language-agnostic comments — same as the text
# protocol's plugins use).
# ---------------------------------------------------------------------------
# <xbar.title>Kitchen Sink (JSON)</xbar.title>
# <xbar.version>1.0</xbar.version>
# <xbar.author>Naveen Kumar</xbar.author>
# <xbar.author.github>navbytes</xbar.author.github>
# <xbar.desc>Every field of Vee's JSON output format in one runnable plugin.</xbar.desc>
# <xbar.dependencies>bash</xbar.dependencies>
#
# Trust declarations (advisory, never enforced): the "Say hello" row below
# is a shell action a user can click, so it is declared honestly.
# <vee.capabilities>exec</vee.capabilities>
# <vee.exec>say</vee.exec>

# ---------------------------------------------------------------------------
# THE OUTPUT
#
# One JSON object, `"vee":1` at the top level. A quoted heredoc (<<'EOF')
# means no shell escaping — the JSON is printed byte for byte.
# ---------------------------------------------------------------------------
cat <<'EOF'
{
  "vee": 1,
  "title": [
    { "text": "Kitchen Sink", "color": "green", "sfimage": "fork.knife" },
    { "text": "✓", "color": "blue", "size": 11 }
  ],
  "items": [
    { "header": true, "text": "Basics" },
    { "text": "Colored, symboled, sized", "color": "purple", "sfimage": "paintpalette", "size": 13 },
    { "text": "Open the docs", "href": "https://vee.navbytes.io" },
    {
      "text": "Say hello (runs a command)",
      "shell": "/usr/bin/say",
      "params": ["hello from the kitchen sink"],
      "terminal": false,
      "tooltip": "Runs in Terminal so you can watch it"
    },
    { "text": "Refresh", "refresh": true },
    { "text": "Disabled row", "disabled": true },
    { "text": "Checked row", "checked": true },

    { "separator": true },
    { "header": true, "text": "Nesting and alternates" },
    {
      "text": "Recent",
      "submenu": [
        {
          "text": "This week",
          "submenu": [
            { "text": "#4210 passed", "color": "green" },
            { "text": "#4209 failed", "color": "red" }
          ]
        },
        { "text": "Last week", "color": "gray" }
      ]
    },
    {
      "text": "Open dashboard",
      "href": "https://ci.example.com/builds",
      "alternate": { "text": "Open dashboard (raw logs)", "href": "https://ci.example.com/builds/raw" }
    },

    { "separator": true },
    { "header": true, "text": "Rich controls" },
    {
      "text": "Load history",
      "sparkline": [1, 2, 3, 5, 8, 13, 8, 5, 3, 2],
      "sparklineColor": "teal",
      "accessoryWidth": 140,
      "accessoryHeight": 20
    },
    {
      "text": "Disk usage",
      "color": "green",
      "progress": 0.72,
      "progressTrackColor": "#333333",
      "accessoryWidth": 90,
      "accessoryHeight": 8
    },
    { "text": "Notifications", "toggle": true },
    { "text": "Volume", "slider": { "min": 0, "max": 100, "value": 40 } },
    {
      "text": "By category",
      "chart": { "kind": "donut", "values": [45, 30, 25], "labels": ["Documents", "Photos", "Apps"], "colors": ["blue", "teal", "orange"] }
    }
  ]
}
EOF
