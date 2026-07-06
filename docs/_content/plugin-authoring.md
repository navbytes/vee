# Plugin authoring reference

A Vee plugin is any executable that prints text to standard output in the xbar/SwiftBar format. This page is the full reference: filenames, menu structure, the parameter table, metadata headers, and the richer features (SF Symbols, ANSI, Markdown, streaming, cron).

If you would rather build menus with typed code than format text by hand, see the [TypeScript SDK](sdk.md).

## Filenames and refresh intervals

The refresh interval is encoded in the filename as `name.INTERVAL.ext`:

```
cpu.5s.sh      → run every 5 seconds
mail.10m.py    → run every 10 minutes
backup.1h.rb   → run every hour
report.1d.js   → run every day
ping.500ms.sh  → run every 500 milliseconds
weather.sh     → no interval → run once / on demand only
```

Interval units: `ms` (milliseconds), `s` (seconds), `m` (minutes), `h` (hours), `d` (days). The interval token is only recognised when it sits immediately before the extension and there is a name in front of it, so `10s.sh` is treated as a plugin named `10s` with no interval, not an anonymous 10-second plugin.

A plugin without an interval token runs on demand (and on launch). You can also drive scheduling with a cron header — see [Cron schedules](#cron-schedules).

Make every plugin executable:

```sh
chmod +x cpu.5s.sh
```

If a file is not marked executable, Vee still tries to run it using its shebang interpreter, falling back to `/bin/bash`. Marking it `+x` is the reliable path.

## Title vs. dropdown

Standard output is split into two parts by the first `---` line:

```
CPU 12%          ← menu-bar title (before ---)
---              ← separator
Top processes    ← dropdown items (after ---)
Details
```

- Everything **before** the first `---` is the **menu-bar title**. You can print multiple title lines; Vee cycles or stacks them.
- Everything **after** `---` is the **dropdown menu**.
- A plugin with no `---` shows only a title and no dropdown.

## Separators and submenus

- `---` on its own line inside the dropdown draws a divider.
- Prefix a line with `--` to nest it one level into a submenu. The item immediately above becomes the submenu's parent. Each extra `--` nests one more level.

```
---
Network
-- Wi-Fi: connected
-- IP: 192.168.1.20
-- Speed
---- Down: 120 Mbps
---- Up: 24 Mbps
```

Here `Network` is a submenu containing `Wi-Fi`, `IP`, and a further `Speed` submenu.

## Line parameters

Append `| key=value key2=value2 …` to any line to attach parameters. Quote values that contain spaces (`title="Open in browser"`), and escape quotes with `\"`.

| Parameter | Description |
|-----------|-------------|
| `color` | Text color — a named color (`red`, `green`, …) or a hex value like `#00ff00`. |
| `font` | Font family name for the text. |
| `size` | Font point size. |
| `length` | Truncate the displayed text to this many characters. |
| `trim` | `true`/`false` — trim surrounding whitespace from the text. |
| `href` | Open this URL when the item is clicked. |
| `shell` / `bash` | Run this command on click. Positional args come from `param0`, `param1`, … |
| `param0`, `param1`, … | Ordered arguments passed to `shell`/`bash`. |
| `terminal` | `true` to run the `shell` command in a visible Terminal window; `false` to run it in the background. |
| `refresh` | `true` — re-run the plugin when the item is clicked. |
| `dropdown` | `false` — show the line only in the menu bar, not the dropdown. |
| `alternate` | `true` — this line is the Option-key alternate of the line above it. |
| `disabled` | `true` — render the item greyed-out and non-clickable. |
| `key` | Keyboard shortcut for the item, active while the menu is open (e.g. `key=Cmd+R`, `key=shift+F2`, `key=cmd+space`). |
| `image` | Base64-encoded image (or file reference) shown next to the text. |
| `templateImage` | Like `image`, but treated as a template image that adapts to light/dark. |
| `sfimage` | SF Symbol name to show as the item's icon (e.g. `sfimage=cpu`). |
| `sfcolor` | Color(s) for the SF Symbol; comma-separated for multicolor symbols. |
| `sfsize` | Point size for the SF Symbol. |
| `sfconfig` | SF Symbol configuration as JSON — `scale` (`small`/`medium`/`large`) and `weight` (e.g. `bold`). Example: `sfconfig='{"scale":"large","weight":"bold"}'`. |
| `symbolize` | `true` — render inline `:symbol.name:` tokens in the text as SF Symbols. |
| `md` / `markdown` | `true` — render the text as inline Markdown (bold, italics, etc.). |
| `ansi` | `true` — interpret ANSI color escape codes in the text. |
| `emojize` | `true`/`false` — convert `:shortcode:` tokens (e.g. `:smile:`) into emoji. |
| `tooltip` | Hover tooltip text. |
| `checked` | `true` — show a checkmark next to the item. |
| `badge` | A short badge/chip shown after the text (e.g. `badge=12`). |
| `shortcut` | Run a macOS Shortcut by name when the item is clicked (e.g. `shortcut="Start Meeting"`). |
| `webview`, `webvieww`, `webviewh` | Open a URL in a standalone WebView window (never inside the menu), with optional width/height. |
| `sparkline` | A comma-separated list of numbers (e.g. `sparkline=1,2,3,4,5`). Clicking the item opens a native Liquid Glass popover that renders the series as an inline Swift Charts sparkline — rich UI without a WebView. |
| `toggle` | `toggle=on` / `toggle=off` (also `true`/`false`/`1`/`0`). Clicking opens a Liquid Glass popover with a switch; flipping it re-invokes the item's `shell=`/`bash=` with the new value. |
| `slider` | `slider=min,max,value` (e.g. `slider=0,100,40`). Clicking opens a Liquid Glass popover with a slider; releasing it re-invokes the item's `shell=`/`bash=` with the chosen value. |

Unknown parameters are preserved rather than dropped, so the format can evolve without breaking existing plugins.

## Rich inline charts (Liquid Glass popovers)

Attach `sparkline=` to a dropdown item to opt it into a **native** rich-UI surface:

```
Load average | sparkline=0.4,0.6,0.9,1.2,0.8,0.5
```

Clicking the item opens an `NSPopover` that renders the numbers as a Swift Charts
line/area sparkline on a macOS 26 Liquid Glass background. This is Vee's answer to
"rich plugin UI without a WebView" — everything is drawn with SwiftUI + Swift
Charts and AppKit, so there is no embedded browser or cross-platform runtime.
Malformed values are skipped; an empty list is ignored.

### Interactive controls (`toggle=` / `slider=`)

Attach `toggle=` or `slider=` to a dropdown item to open an **interactive**
Liquid Glass popover — a live switch or slider, again drawn natively with SwiftUI
and AppKit (no WebView, no embedded runtime):

```
Wi-Fi | toggle=on shell=/usr/local/bin/wifi.sh
Volume | slider=0,100,40 shell=/usr/local/bin/volume.sh
```

When you change the control, Vee re-invokes the item's `shell=`/`bash=` command
with the new value provided two ways, so you can read whichever is convenient:

- the `VEE_CONTROL_VALUE` environment variable, and
- the value appended as the command's final argument.

Toggles pass `1`/`0`; sliders pass the numeric value (integers without a trailing
`.0`). Add `refresh=true` to re-render the menu bar after the command runs.

```bash
#!/bin/bash
# volume.sh — called with the new slider value
osascript -e "set volume output volume $VEE_CONTROL_VALUE"
```

A slider needs three numbers (`min,max,value`) with `min < max`; the value is
clamped into range. Malformed controls are ignored.

> **Proposal, subject to change.** The `sparkline=`, `toggle=`, and `slider=`
> syntax (and the popover surface they opt into) are an early proposal; the exact
> convention may still evolve.

## Metadata headers

Put `<xbar.*>` / `<swiftbar.*>` tags anywhere in the file (usually in a comment block near the top). They are scanned regardless of the comment syntax, so they work in any language.

| Tag | Purpose |
|-----|---------|
| `<xbar.title>` | Human-readable plugin name. |
| `<xbar.version>` | Plugin version. |
| `<xbar.author>` | Author name. |
| `<xbar.author.github>` | Author's GitHub handle. |
| `<xbar.desc>` | One-line description. |
| `<xbar.image>` | Preview image URL. |
| `<xbar.dependencies>` | Comma-separated tools the plugin needs (e.g. `python3,jq`). |
| `<xbar.abouturl>` | A link to the plugin's homepage. |
| `<xbar.var>` | A typed, user-editable preference — see [Preferences](preferences.md). |
| `<swiftbar.schedule>` | A cron schedule (one or more, `|`-separated). |
| `<swiftbar.type>streamable</swiftbar.type>` | Marks the plugin as a long-running streaming plugin. |
| `<swiftbar.runInBash>` | Whether to run the script through bash. |
| `<swiftbar.refreshOnOpen>` | Re-run the plugin each time its menu opens. |
| `<swiftbar.environment>` | Inline environment variables, e.g. `[VAR1=a, VAR2=b]`. |
| `<swiftbar.hideAbout>` | Hide the default "About" item. |

The `<swiftbar.*>` tags use the same names as their `<xbar.*>` counterparts where they overlap.

## SF Symbols

Use Apple's SF Symbols as icons or inline glyphs:

- As an item icon: `Some item | sfimage=bolt.fill`
- Colored: `Battery | sfimage=battery.100 sfcolor=green`
- Inline in text: `Status :checkmark.circle: | symbolize=true`

Browse names with Apple's [SF Symbols app](https://developer.apple.com/sf-symbols/).

## ANSI color

If your tool emits ANSI escape codes (many CLIs do), pass `ansi=true` to have Vee interpret them:

```sh
echo -e "\033[32mOK\033[0m | ansi=true"
```

## Markdown

Render inline Markdown with `md=true`:

```
**Bold** and _italic_ | md=true
```

## Streaming

A streaming plugin stays running and pushes updates instead of being re-run on a timer. Mark it with `<swiftbar.type>streamable</swiftbar.type>` and print a `~~~` line to signal "the menu that follows replaces the current one." Each block between `~~~` separators is a full menu render. Vee restarts the process with backoff if it exits.

```bash
#!/bin/bash
# <swiftbar.type>streamable</swiftbar.type>
while true; do
  echo "~~~"
  echo "⏱ $(date +%T)"
  sleep 1
done
```

## Cron schedules

Instead of (or in addition to) a filename interval, schedule a plugin with a 5-field cron expression:

```bash
# <swiftbar.schedule>0 9 * * 1-5</swiftbar.schedule>
```

The fields are `minute hour day-of-month month day-of-week`, supporting `*`, single values, lists (`a,b`), ranges (`a-b`), and steps (`*/n`). Day-of-week is `0`–`6` (0 = Sunday). Multiple schedules can be separated with `|`.

## Environment variables Vee injects

Every plugin run inherits your shell environment plus these variables:

**xbar compatibility**

- `XBARDarkMode` — `true` when the system is in dark mode, else `false`.

**SwiftBar compatibility**

- `SWIFTBAR` — `1` when running under Vee's SwiftBar-compatible runtime.
- `SWIFTBAR_VERSION`, `SWIFTBAR_BUILD` — the app version.
- `SWIFTBAR_PLUGINS_PATH` — the plugins directory.
- `SWIFTBAR_PLUGIN_PATH` — the absolute path of this plugin.
- `SWIFTBAR_PLUGIN_CACHE_PATH`, `SWIFTBAR_PLUGIN_DATA_PATH` — per-app cache and data directories.
- `OS_APPEARANCE` — `Dark` or `Light`.
- `OS_VERSION_MAJOR`, `OS_VERSION_MINOR`, `OS_VERSION_PATCH` — the macOS version.

**Vee-native**

- `VEE` — `1`.
- `VEE_VERSION` — the app version.
- `VEE_PLUGIN_PATH` — the absolute path of this plugin.
- `VEE_CONTROL_VALUE` — set only on a re-invocation triggered by an interactive `toggle=`/`slider=` item, carrying the committed value.

Any values from the plugin's declared `<xbar.var>` [preferences](preferences.md) are also injected as environment variables (they take precedence over the above).

## Worked examples

### 1. Bash — CPU usage with a submenu

Filename: `cpu.5s.sh`

```bash
#!/bin/bash
# <xbar.title>CPU</xbar.title>
# <xbar.desc>Shows CPU load in the menu bar.</xbar.desc>
# <xbar.author>You</xbar.author>

load=$(uptime | awk -F'load average:' '{print $2}' | awk -F, '{print $1}' | xargs)

echo "CPU $load | sfimage=cpu"
echo "---"
echo "Top processes"
top -l 1 -o cpu -n 5 -stats command,cpu | tail -n 5 | while read -r line; do
  echo "--$line | font=Menlo"
done
echo "---"
echo "Activity Monitor | bash=/usr/bin/open param0=-a param1='Activity Monitor' terminal=false"
echo "Refresh | refresh=true"
```

### 2. Python — GitHub notifications with a preference and a link

Filename: `github.10m.py`

```python
#!/usr/bin/env python3
# <xbar.title>GitHub Notifications</xbar.title>
# <xbar.desc>Unread GitHub notifications count.</xbar.desc>
# <xbar.dependencies>python3</xbar.dependencies>
# <xbar.var>string(GITHUB_TOKEN=): A GitHub personal access token.</xbar.var>
# <vee.network>api.github.com</vee.network>
# <vee.secrets>GITHUB_TOKEN</vee.secrets>

import os, json, urllib.request

token = os.environ.get("GITHUB_TOKEN", "")
if not token:
    print("GH ⚙️")
    print("---")
    print("Set a token in Vee settings")
    raise SystemExit

req = urllib.request.Request(
    "https://api.github.com/notifications",
    headers={"Authorization": f"Bearer {token}"},
)
items = json.load(urllib.request.urlopen(req))

print(f"GH {len(items)} | sfimage=bell")
print("---")
for n in items[:10]:
    title = n["subject"]["title"]
    print(f"{title} | href=https://github.com/notifications")
print("---")
print("Refresh | refresh=true")
```

This example also declares a [preference](preferences.md) (`<xbar.var>`) and its [trust](trust-model.md) footprint (`<vee.network>`, `<vee.secrets>`).

### 3. Bash — streaming clock

Filename: `clock.sh` (no interval — streaming drives the updates)

```bash
#!/bin/bash
# <xbar.title>Clock</xbar.title>
# <swiftbar.type>streamable</swiftbar.type>

while true; do
  echo "~~~"
  echo "🕒 $(date +%H:%M:%S)"
  echo "---"
  echo "$(date '+%A, %B %d')"
  sleep 1
done
```

## See also

- [Trust model](trust-model.md) — declare what your plugin accesses.
- [Preferences](preferences.md) — declare typed settings and secrets.
- [CLI and URL actions](cli-and-urls.md) — trigger refresh/notify from a plugin.
- [Troubleshooting](troubleshooting.md) — when a plugin does not appear or errors.
