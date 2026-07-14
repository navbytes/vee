# Plugin authoring reference

A Vee plugin is any executable that prints text to standard output in the xbar/SwiftBar format. This page is the full reference: filenames, menu structure, the parameter table, metadata headers, and the richer features (SF Symbols, ANSI, Markdown, streaming, cron).

If you would rather build menus with typed code than format text by hand, see the [Plugin SDKs](sdk.md) (TypeScript, Python, and Go). For a structured alternative to the text protocol, see the [JSON output format](json-output.md).

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

## Section headers

Mark a line `header=true` to render it as a real, non-interactive section header — AppKit's native section-header row — instead of a `disabled=true` line dressed up to look like one:

```
---
Accounts | header=true
Checking
Savings
---
Cards | header=true
Visa ···· 4242
```

A header row is title-only: it ignores click/appearance params (`href=`, `color=`, `md=`, …) since AppKit's native section header renders plain text and never fires an action. Keep it at the same indentation as the items it introduces — like `disabled=true` today, it doesn't nest anything under itself.

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
| `header` | `true` — render this line as a real, non-interactive [section header](#section-headers) instead of a normal item. |
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
| `sparkline` | A comma-separated list of numbers (e.g. `sparkline=1,2,3,4,5`). Renders as a small chart **inline in the menu row**; clicking the item also opens a fuller native Liquid Glass Swift Charts popover. |
| `toggle` | `toggle=on` / `toggle=off` (also `true`/`false`/`1`/`0`). Clicking opens a Liquid Glass popover with a switch; flipping it re-invokes the item's `shell=`/`bash=` with the new value. |
| `slider` | `slider=min,max,value` (e.g. `slider=0,100,40`). Clicking opens a Liquid Glass popover with a slider; releasing it re-invokes the item's `shell=`/`bash=` with the chosen value. |
| `progress`, `trackcolor`, `progressw`, `progressh` | `progress=<0..1>` or `progress=value,max` (e.g. `progress=0.72` or `progress=23.65,100`). Draws a real capsule bar **inline in the menu row**. Fill uses `color=`; `trackcolor=` is the groove, `progressw=`/`progressh=` set the bar size in points. |
| `accessory` | `leading` / `trailing` — which edge of the row a `progress=`/`sparkline=` accessory anchors to (default `trailing`, today's rendering). See [Accessory placement](#accessory-placement-accessory). |

Unknown parameters are preserved rather than dropped, so the format can evolve without breaking existing plugins.

## Rich inline charts (Liquid Glass popovers)

Attach `sparkline=` to a dropdown item to render a compact chart **inline in the
menu row** — the same in-row custom view `progress=` uses:

```
Load average | sparkline=0.4,0.6,0.9,1.2,0.8,0.5
```

Clicking the item still opens the richer surface: an `NSPopover` that renders the
same numbers as a full Swift Charts line/area sparkline on a macOS 26 Liquid Glass
background. This is Vee's answer to "rich plugin UI without a WebView" —
everything is drawn with SwiftUI + Swift Charts and AppKit, so there is no
embedded browser or cross-platform runtime. Malformed values are skipped; an
empty list is ignored (no inline chart, no popover). A single value has no series
to chart, so it draws as a flat centered baseline instead.

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

### Inline progress bars (`progress=`)

Unlike the popover items above, `progress=` draws a **real capsule bar right in
the menu row** — no click, no popover. It's the native answer to hand-drawn
block-glyph bars:

```
$23.65 of $100 | progress=23.65,100 color=#36C26E trackcolor=#3C4046 progressw=210
Disk | progress=0.88 color=#F5A623
```

- `progress=<0..1>` (a fraction) **or** `progress=value,max` (mirrors `slider=`'s
  grammar). The result is always clamped to `0…1`.
- The **fill** color is the row's `color=`; `trackcolor=` sets the groove.
- `progressw=` / `progressh=` set the bar's width/height in points (defaults 120×6).
- The row's text renders to the left of the bar; the row auto-sizes so the label
  never truncates. Unknown to xbar/SwiftBar, so plugins stay portable (they just
  ignore it).

The gauge itself is display-only (it doesn't fire a click by being a gauge), but
the row can still carry its own `href=`/`shell=` action or a submenu, exactly
like a plain item.

If a row sets both `progress=` and `sparkline=`, the progress bar takes the
inline view; `sparkline=`'s click-to-popover still opens as normal either way.

### Accessory placement (`accessory=`)

Both `progress=` and `sparkline=` anchor their accessory (bar/chart) to the
row's **trailing** edge by default, with the label filling the rest — today's
rendering. Set `accessory=leading` to flip it: the accessory anchors to the
row's leading edge instead, with the label filling the remaining trailing
space.

```
Budget | progress=0.72 accessory=leading
```

Omit `accessory=` (or set `accessory=trailing`) for today's default.

## Searchable filter panel

Big menus — dozens of items across nested submenus — are slow to scan. Opt a
plugin into a **searchable filter panel** and its dropdown gains a **Search…**
row (⌘F) that opens a Spotlight-like popover: type to filter *every* item at once
(including those nested inside submenus), flattened into a ranked list, each with
a breadcrumb of its parent groups.

```
# <vee.filter>true</vee.filter>
```

- **Fuzzy matching** — `gh` finds `GitHub`; multiple words are ANDed together.
- **Keyboard-driven** — ↑/↓ move the highlight, Return activates, Esc closes.
- Activating a row runs its **normal action** — `href`, `shell`/`bash`,
  `shortcut`, `refresh`, and the `toggle`/`slider`/`sparkline` popovers all work
  exactly as they do from the menu.

The panel is an *addition*, not a replacement: the native menu, its trust row,
and Vee's own controls all stay exactly where they are.

### Global hotkey (`<vee.shortcut>`)

Bind a system-wide hotkey that opens the panel from anywhere — no need to open
the menu first, and Vee doesn't have to be the active app:

```
# <vee.shortcut>cmd+shift+k</vee.shortcut>
```

Modifiers are `cmd`/`command`/`⌘`, `shift`/`⇧`, `opt`/`option`/`alt`/`⌥`, and
`ctrl`/`control`/`⌃`; the key can be a letter, a digit, `F1`–`F12`, `space`,
`return`, `tab`, `escape`, or an arrow. Order doesn't matter and it's
case-insensitive (`⌘⇧K` works too), but at least one modifier is required. Vee
registers it with the system hotkey API, so **no Accessibility permission is
needed**; if the combination is already taken system-wide, Vee logs it and moves
on. The user stays in control: a plugin's hotkey can be **turned off or rebound**
from the plugin's Settings, where its live status (active / in-use / invalid) is
shown.

Both tags are strictly opt-in — omit them and the plugin behaves exactly as
before. Whatever a plugin declares, Vee surfaces under its **Features** — in the
menu's capabilities area and the plugin's Settings window, and on the install
sheet — so a global hotkey a plugin grabs is always visible and never a
surprise. You can also preview a plugin's search from the terminal without
installing it: see [`vee search`](cli-and-urls.md#vee-search).

## Widgets

By default your plugin's widget tile is a **scrape** of its menu-bar line —
whatever `color=`/`sfimage=` is on the title, plus a `progress=`/`sparkline=`
if the first row has one. That's automatic; every plugin already has a widget
representation with no changes.

For a **rich** tile — real data laid out per widget size, not a caricature of
the menu bar — opt a plugin into the widget surface contract:

```
# <vee.surface>both</vee.surface>
```

- `<vee.surface>menu</vee.surface>` (or omit the tag) — unchanged: a normal
  menu-bar plugin, scraped for its widget tile.
- `<vee.surface>both</vee.surface>` — served in the menu as usual, **and**
  invoked a second time in widget mode to produce a rich widget card.
- `<vee.surface>widget</vee.surface>` — **widget-only**: no status item, no
  menu bar presence at all. The plugin exists only to feed a widget.

The widget-mode cadence needs no separate tag — it reuses the plugin's
**filename interval** (the same field the menu bar uses), with only a small
safety floor: `max(filename interval, 10s)`. Because Vee is an always-running
app, it pushes widget reloads the moment new data arrives (rather than waiting
on WidgetKit's passive budget, which only applies when an app isn't running), so
a `cpu.5s.sh` widget can track near-real-time data straight from the menu-bar
plugin's own cadence. A widget-only plugin whose filename carries no interval
falls back to the 10-second floor.

### `VEE_TARGET`

Every run gets a `VEE_TARGET` environment variable:

- `VEE_TARGET=menu` — a normal run; print the usual xbar/SwiftBar text (or
  [JSON](json-output.md)).
- `VEE_TARGET=widget` — a widget-mode run; print **one JSON object** (the
  "card", schema below) to stdout and nothing else.

Branch on it like Scriptable's `config.runsInWidget`. If your plugin ignores
`VEE_TARGET=widget` and prints menu text anyway, Vee falls back to scraping
that text — graceful degradation, never a crash.

### The card

```json
{
  "vee_widget": 1,
  "template": "stat",
  "title": "Revenue",
  "symbol": "chart.line.uptrend.xyaxis",
  "tint": "green",
  "value": "$18.2k",
  "caption": "today",
  "detail": "214 orders",
  "status": "ok",

  "progress": 0.72,
  "trend": [12.1, 13.4, 12.9, 15.0, 18.2],

  "items": [
    { "label": "Orders",  "value": "214", "symbol": "bag",           "tint": "blue" },
    { "label": "Refunds", "value": "3",   "symbol": "arrow.uturn.left", "tint": "red" }
  ],

  "actions": [
    { "label": "Refresh", "kind": "refresh" },
    { "label": "Open",    "kind": "href",     "url": "https://dash.example.com" }
  ],

  "refresh_after": 900,
  "stale_after": 3600
}
```

| Field | Type | Meaning |
|---|---|---|
| `vee_widget` | int | Payload schema version (currently `1`). |
| `template` | enum | `stat` \| `gauge` \| `trend` \| `list` \| `board`. Unknown → `stat` + a Debug diagnostic. |
| `title` | string? | Tile heading (the plugin/metric name). |
| `symbol` | string? | SF Symbol name for the glyph. |
| `tint` | color? | Named (`green`) or `#rrggbbaa`. |
| `value` | string? | The headline value, already formatted by the plugin. |
| `caption` | string? | Small secondary line (e.g. "today"). |
| `detail` | string? | One more line of context. |
| `status` | enum? | `ok` \| `warning` \| `error` — drives styling and the health roll-up. |
| `progress` | double? | `0…1`, clamped; the `gauge` template's fill. |
| `trend` | [double]? | The `trend` template's series. |
| `items` | [Item]? | Rows for `list`/`board`: `{label, value?, symbol?, tint?}`. |
| `actions` | [Action]? | Up to two rendered as buttons — see below. |
| `refresh_after` | int? | Seconds; a hint for the next widget reload. |
| `stale_after` | int? | Seconds; when the tile should show a stale treatment (else the interval-derived default). |

Unknown top-level keys are ignored (forward-compatible); an invalid value
(bad `progress`, a non-finite `trend` entry, an unsafe `href` URL) degrades to
`nil`/dropped with a diagnostic, visible in the plugin's Debug console —
never a crash.

### Templates

Five native SwiftUI templates, each adapting across the small/medium/large
widget families — describe your data, Vee draws it:

- **stat** — glyph, big `value` in `tint`, `title`/`caption`. The default.
- **gauge** — stat + a native gauge from `progress`.
- **trend** — stat + a sparkline from `trend`.
- **list** — `title` header + `items` as rows, truncated per family (small
  shows the headline `value`; medium ≤3 rows; large ≤8).
- **board** — a compact grid of `items` as stat cells (a KPI board); small
  collapses to the headline.

### Actions

Up to two `actions` render as buttons:

- `refresh` — re-runs this plugin.
- `href` — opens a URL (scheme-filtered like menu `href=`: `http`/`https`/
  custom app deep links; never `file`/`javascript`/…).
- `shortcut` — runs a named macOS Shortcut (`name`), like menu `shortcut=`.

There is deliberately **no `shell` action** — a widget button must not run an
arbitrary command without the menu's context.

### Building the card with the SDK

The [TypeScript, Python, and Go SDKs](sdk.md) all have `Stat`/`Gauge`/`Trend`/
`List`/`Board` builders that emit this JSON for you:

```ts
import { Stat } from "./src/vee.ts";

if (process.env.VEE_TARGET === "widget") {
  Stat({
    title: "Revenue",
    symbol: "chart.line.uptrend.xyaxis",
    tint: "green",
    value: "$18.2k",
    status: "ok",
    actions: [{ kind: "refresh", label: "Refresh" }],
  }).print();
} else {
  // ordinary menu-bar output
}
```

See [Plugin SDKs](sdk.md#widget-cards) for the Python/Go equivalents.

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
| `<swiftbar.hideRunInTerminal>` | Hide the "Run in Terminal…" item. |
| `<swiftbar.hideLastUpdated>` | Hide the "Updated…" timestamp item. |
| `<swiftbar.hideDisablePlugin>` | Hide the "Disable Plugin" item. |
| `<swiftbar.hideSwiftBar>` | Hide the app (Vee) submenu. |
| `<swiftbar.persistentWebView>` | Keep a `webview=` window alive across refreshes instead of recreating it. |

The `<swiftbar.*>` tags use the same names as their `<xbar.*>` counterparts where they overlap.

### Vee-native tags (`<vee.*>`)

Vee adds a few tags of its own. All are opt-in — omit them for the classic behavior.

| Tag | Purpose |
|-----|---------|
| `<vee.filter>` | `<vee.filter>true</vee.filter>` opts the dropdown into the [searchable filter panel](#searchable-filter-panel). |
| `<vee.shortcut>` | `<vee.shortcut>cmd+shift+k</vee.shortcut>` binds a [global hotkey](#global-hotkey-veeshortcut) that opens the search panel from anywhere. |
| `<vee.surface>` | `menu` (default) / `both` / `widget` — which output surface(s) the plugin serves. See [Widgets](#widgets). |
| `<vee.timeout>` | `<vee.timeout>90</vee.timeout>` overrides the default 30s execution timeout for this plugin. Accepts a plain number of seconds or a duration token (`ms`/`s`/`m`/`h`/`d`, same format as [filename intervals](#filenames-and-refresh-intervals)), e.g. `<vee.timeout>2m</vee.timeout>`. Clamped to 1s–1h. |
| `<vee.capabilities>`, `<vee.network>`, `<vee.secrets>`, `<vee.filesystem.read>` / `<vee.filesystem.write>`, `<vee.exec>` | Declare the plugin's [trust footprint](trust-model.md). |

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
- `VEE_PLUGIN_ID` — this plugin's id (its filename); pass it as `plugin=` to `swiftbar://notify` for an actionable alert (see [URL actions](cli-and-urls.md#the-notify-action)).
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
