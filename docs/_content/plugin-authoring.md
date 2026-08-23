---
title: "Plugin authoring reference"
description: "The full Vee plugin reference: filenames and intervals, menu structure, line parameters, metadata headers, SF Symbols, ANSI, Markdown, streaming, and cron."
sidebar:
  label: "Plugin authoring"
  order: 3
head:
  - tag: link
    attrs:
      rel: "alternate"
      type: "text/markdown"
      href: "/guide/plugin-authoring.md"
      title: "Markdown source"
  - tag: title
    content: "Plugin authoring reference — Vee docs"
---
A Vee plugin is any executable that prints text to standard output in the xbar/SwiftBar format. This page is the full reference: filenames, menu structure, the parameter table, metadata headers, and the richer features (SF Symbols, ANSI, Markdown, streaming, cron).

If you would rather build menus with typed code than format text by hand, see the [Plugin SDKs](sdk.md) (TypeScript, Python, and Go). For a structured alternative to the text protocol, see the [JSON output format](json-output.md).

## The authoring loop

Before the reference, the workflow it is meant to be read alongside. Vee gives
you a save-driven loop that needs no app running and no plugin installed:

```sh
vee dev ./cpu.10s.sh
```

Keep that in a split terminal beside your editor. Every save re-runs the file and
repaints the menu tree Vee would build, together with any lint findings. A save
that breaks the script shows the exit code and stderr and keeps watching, so you
never have to restart the loop over a typo.

Two flags make it a design tool rather than only a debugger:

- **`vee dev --text menu.txt`** treats the file as plugin *output* and never
  executes it. Sketch the shape of a menu — sections, submenus, colors, charts —
  as plain text, watch it render, and only then write the script that produces
  it. Nothing runs, so the file needs no shebang and no execute bit.
- **`vee dev --push ./cpu.10s.sh`** additionally shows each save as a real status
  item in the menu bar, with no file written to your plugins folder. The terminal
  shows you the structure; the menu bar shows you Vee's actual render.

For inline diagnostics in your editor, `vee lint --format compact` emits
`path:line:col: severity: message`, which VS Code, vim, and emacs already parse —
no extension required. See [Debugging and testing plugins](debugging.md) for the
loop's full flag list, a copy-pasteable VS Code `problemMatcher`, and a note on
which file a finding is attributed to.

Editing a plugin that is already installed works too: Vee watches each plugin
file and re-reads it shortly after you save, so the menu bar keeps up without a
relaunch.

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

In the search panel, section headers render as dimmed context rows and become part of each row's breadcrumb (e.g. `Accounts › Checking`); they are searchable, so typing a section name surfaces its rows. Header submenus — a `header=true` line with child items indented under it — never surface in the search results.

## Line parameters

Append `| key=value key2=value2 …` to any line to attach parameters. Quote values that contain spaces (`title="Open in browser"`), and escape quotes with `\"`.

A literal `|`, backslash, or newline in the display text (or in a quoted value) must be escaped as `\|`, `\\`, or `\n` — otherwise an unescaped `|` is read as the params delimiter and truncates the item, and a raw newline splits it into two corrupted lines. The bundled [TypeScript, Python, and Go SDKs](sdk.md) escape these automatically for any text/value you pass in; only hand-written plugin output needs to do it explicitly.

Every parameter below is generated from `docs/api/params.json`, the same
record `vee lint` and the three SDKs are checked against — so a parameter
that exists is listed here, and one listed here exists.

<!-- include: _generated/params-table.md -->

Unknown parameters are preserved rather than dropped, so the format can evolve without breaking existing plugins.

Every chart parameter above belongs to one specific chart. For the whole set
side by side — which charts exist, how each is spelled on the text, JSON, and
widget surfaces, and which options apply to which — see [Charts](charts.md).

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

The chart takes the same size and colour vocabulary as the other two inline
accessories — `<control>w`, `<control>h`, `<control>color`:

```
Load average | sparkline=0.4,0.6,0.9,1.2 sparklinew=120 sparklineh=18 sparklinecolor=teal
Requests     | sparkline=12,40,31,55,48 sparklinew=full
```

`sparklinew=`/`sparklineh=` set the chart size in points (defaults 90×20).
`sparklinew=full` stretches it across whatever width the row actually has,
exactly as `progressw=full` and `chartw=full` do — a menu is as wide as its
widest row, so a fixed width cannot fill a menu some *other* row sizes.
`sparklinecolor=` sets the line colour; without it the chart uses the row's
`color=`, and without that, the control accent.

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
$23.65 of $100 | progress=23.65,100 color=#36C26E progresstrackcolor=#3C4046 progressw=210
Disk | progress=0.88 color=#F5A623
```

- `progress=<0..1>` (a fraction) **or** `progress=value,max` (mirrors `slider=`'s
  grammar). The result is always clamped to `0…1`.
- The **fill** color is the row's `color=`; `progresstrackcolor=` sets the groove.
  (`trackcolor=` is the deprecated spelling and still works.)
- `progressw=` / `progressh=` set the bar's width/height in points (defaults 120×6).
  `progressw=full` stretches the bar across whatever width the row actually has,
  less the row's own text — the same knob a `stackedbar=` takes as `chartw=full`.
  A menu is as wide as its widest row, so a fixed `progressw=` can't fill a menu
  whose width some *other* row decides; `full` can. It never widens the menu
  itself, and in a menu too narrow to stretch into it falls back to 120pt.

```
Disk | progress=0.88 progressw=full
 | progress=0.62 progressw=full progressh=10
```

- The row's text renders to the left of the bar; the row auto-sizes so the label
  never truncates. Unknown to xbar/SwiftBar, so plugins stay portable (they just
  ignore it).

The gauge itself is display-only (it doesn't fire a click by being a gauge), but
the row can still carry its own `href=`/`shell=` action or a submenu, exactly
like a plain item.

If a row sets more than one inline accessory, the first of
`progress=` → `sparkline=` → chart takes the in-row view; the click-to-popover
that `sparkline=` and the charts opt into still opens as normal either way.

### Share charts (`pie=`, `donut=`, `stackedbar=`)

Where `sparkline=` shows a value *over time*, these show how a total *divides
up*. All three take the same data — one series of non-negative numbers read as
shares of a whole — so switching shapes means changing one word:

```
By category | pie=45,30,25 chartlabels=Documents,Photos,Apps
By volume   | donut=512,256,128 chartlabels="Macintosh HD,Backup,Scratch"
Budget      | stackedbar=60,25,15 chartlabels=Used,Cache,Free
```

The chart draws **inline in the menu row** (a small pie, donut, or capsule bar,
using the same accessory slot `progress=` and `sparkline=` use). Clicking the row
opens a Liquid Glass Swift Charts popover with the chart at full size and a
legend naming every segment with its percentage — the popover is where
`chartlabels=` becomes visible, since a menu row has no space for them. A donut
also shows the series total in its hole.

**Size.** An inline chart is small by default — it shares a menu row with its
label. `chartw=`/`charth=` make it as large as the row can carry (clamped to
8–200 points); the row grows to fit. A pie or donut is a circle, so either knob
sizes both sides:

```
 | pie=45,30,25 charth=56 chartlabels=Documents,Photos,Apps
Budget | stackedbar=60,25,15 chartw=200 charth=16
```

Leaving the text before `|` empty, as in the first line, gives the chart the
whole row — useful when a legend of ordinary rows underneath already names the
segments.

`chartw=full` stretches a **stacked bar** to the width the row actually has,
rather than a number of points:

```
 | stackedbar=60,25,15 chartw=full charth=14
By model | stackedbar=60,25,15 chartw=full
```

A menu is as wide as its widest row, so a fixed `chartw=` can't fill a menu whose
width some *other* row decides — `full` can. A row with text keeps it, and the
chart takes the width that remains; a row with none gives the chart everything
between the menu's insets. A full-width chart never widens the menu itself, and
in a menu too narrow to stretch into it falls back to its normal size.
`progress=` takes the same knob, spelled `progressw=full`.

`full` is a *width* control, and a pie or donut has no free width — its width is
its diameter, so stretching one would make the row as tall as the menu is wide.
`chartw=full` on a `pie=`/`donut=` is therefore ignored with a warning; size a
circle with `chartw=`/`charth=` points instead.

**Colors.** Segments take Vee's built-in categorical palette by position, so
segment 1 is always the same hue no matter how many segments a plugin emits.
The palette is eight fixed slots, selected separately for light and dark mode and
checked for color-blind separation — so you don't have to pick colors at all.
Override them positionally with `chartcolors=` when your data has its own
conventional colors:

```
Storage | donut=512,256,128 chartcolors=blue,teal,orange
Status  | stackedbar=8,1,3 chartcolors=,,red
```

Leave an entry blank (as in `chartcolors=,,red` above) to recolor just one
segment and keep the palette for the rest. Unlike `sfcolor=`, positions are never
compacted: a blank or malformed entry stays a hole rather than sliding the next
color onto the wrong segment. A name Vee doesn't recognise also falls back to the
palette, so a typo costs you one segment's color, never the alignment of the
rest.

**Rules the parser enforces**, so a chart never misrepresents its data:

- Every value must be a finite number and `>= 0`, and at least one must be
  positive. A negative, non-numeric, or all-zero series is ignored (with a
  diagnostic in `vee lint`) rather than drawn wrong.
- At most **8 segments**. A longer series isn't truncated — that would silently
  rescale every slice that survived — the first 7 are kept and the rest are
  summed into a neutral **"Other"** segment, so the shares still add up to your
  own total.
- `chartlabels=`/`chartcolors=` are comma-separated, so a segment name can't
  itself contain a comma. Names with spaces are fine — quote the whole list, as
  in `chartlabels="Macintosh HD,Backup,Scratch"`.

`vee show` renders all three kinds as one segmented block bar (a terminal can't
draw sectors); `vee render` names the shape.

> **Proposal, subject to change.** Like `sparkline=`/`toggle=`/`slider=`, the
> chart syntax is an early proposal; the exact convention may still evolve.

### Accessory placement (`accessory=`)

`progress=`, `sparkline=`, and the share charts anchor their accessory
(bar/chart) to the row's **trailing** edge by default, with the label filling the
rest — today's rendering. Set `accessory=leading` to flip it: the accessory
anchors to the row's leading edge instead, with the label filling the remaining
trailing space.

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

**Before typing (idle state):** the panel mirrors your dropdown's structure — section
headers (`header=true`), separators (`---`), and non-actionable rows (`disabled=true`,
plain sub-text) all appear dimmed and non-selectable, just like the native menu. This
lets users browse and orient themselves without typing. Keyboard selection skips dimmed
rows; only actionable rows can be activated with Return or click.

**While typing:** results flatten into a ranked list. Dimmed info rows match the search
haystack and display, but stay non-activatable — you search to find what you're after,
or just navigate structure when exploring.

**Section titles as context:** headers join the breadcrumb of rows under them (e.g.
`Accounts › Checking`), so typing a section name surfaces all its rows. Nested submenus'
headers and separators don't render as rows themselves — their structure is carried by
breadcrumbs like `Tools › Nested › Item`. Header submenus (a `header=true` line with
children indented under it) never surface in search.

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

The plugin's Settings also chooses **what the hotkey opens** — the search panel
(the default) or the plugin's window. Nothing is given up either way: the window
carries the same search field. With **Window** selected, pressing the hotkey when
the window is already open brings it back to the front, which is the quickest way
back to a window you have unpinned and covered up.

Both tags are strictly opt-in — omit them and the plugin behaves exactly as
before. Whatever a plugin declares, Vee surfaces under its **Features** — in the
menu's capabilities area and the plugin's Settings window, and on the install
sheet — so a global hotkey a plugin grabs is always visible and never a
surprise. You can also preview a plugin's search from the terminal without
installing it: see [`vee search`](cli-and-urls.md#vee-search).

### Leaving a plugin open in a window

The search panel closes on the next click, which is the wrong shape when what you
wanted was to *watch* something. **Open in Window**, in a plugin's own dropdown
beside Refresh and Debug, opens the same surface as a window you can move to
another display and leave open — or press the panel's **keep open** button in its
top-right corner to promote the panel already in front of you.

A window is not a snapshot. It keeps updating on the plugin's own refresh
interval, so a one-second `sparkline=` really does move once a second — something
a Notification Center widget cannot do, since WidgetKit floors refresh at five
minutes. It works for **any** plugin, with no `<vee.*>` declaration required.

- **One window per plugin**, as many plugins at once as you like. Opening a
  plugin that already has a window brings that window forward instead of stacking
  a second one.
- **Pin or unpin** with the button in the title bar. A pinned window floats above
  other apps, follows you across Spaces, and stays visible over a full-screen
  app; an unpinned one behaves like an ordinary window. New windows are pinned,
  and Vee remembers your choice per plugin until it quits.
- **Find them again** under **Detached Windows** in Vee's own menu, which lists
  every open window and brings one to the front. (Vee has no Dock icon, so this
  and the plugin's hotkey are the reliable ways back to a window you have
  unpinned and covered.)
- **When a plugin stops reporting** — disabled, removed, or erroring — its window
  keeps the last output on screen and says it is stale, rather than quietly
  freezing on a number that looks current.

Windows are per-session: they do not reopen after you quit Vee.

Everything the dropdown renders appears in the window — nested submenus,
separators, section headers, colors and ANSI, icons, and the full rich-row family
(`progress=`, `sparkline=`, `pie=`/`donut=`/`stackedbar=`, `toggle=`, `slider=`).
A `toggle=` or `slider=` is live in the row: change it and the plugin's command
runs, exactly as it does from the popover.

Two things are deliberately not reproduced, because they only mean anything
inside an open menu. An `⌥` alternate is shown as an ordinary row of its own
rather than something you hold a modifier to reveal — so it is visible and
clickable, which is more than the dropdown offers. Per-row `key=` equivalents are
not bound.

### Cross-plugin search ("Search All Plugins")

The panel above searches one plugin at a time. **Search All Plugins…**, in
Vee's main menu-bar menu rather than any single plugin's, merges *every
enabled* plugin's current menu into one panel — regardless of whether a
plugin opted into `<vee.filter>` — with each row breadcrumb-prefixed by its
plugin's name (itself part of the fuzzy match, so typing a plugin's name
surfaces its rows). Selecting a row still runs that row's own plugin's
action, never a different plugin's. It has its own opt-in global hotkey, off
by default with no preset combination — set one in Vee's General settings.

## Widgets

Plugins can also render as native desktop and Notification Center widgets —
automatically from their menu-bar line, or as a rich **widget card** they print
themselves. That surface has its own page: [Widgets](widgets.md).

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

If your tool emits ANSI escape codes (many CLIs do), Vee interprets them by default — no parameter needed:

```sh
echo -e "\033[32mOK\033[0m"
```

Pass `ansi=false` to turn this off and show the raw escape codes as text instead.

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

## Publishing your plugin

Vee reads plugins from a folder, so "distributing" one can be as simple as
sending someone a file. There are three routes, in increasing order of reach.

### 1. Share the file

Any executable with an interval in its filename is a complete, self-contained
plugin. Someone drops it in their plugins folder and it runs — no packaging, no
manifest, no install step.

Two courtesies make a shared plugin pleasant to receive:

- **Ship it without the executable bit**, so the recipient reads the source
  before marking it `+x`. The bundled [examples](https://github.com/navbytes/vee/tree/main/plugins/showcase)
  do exactly this.
- **Fill in the metadata.** `<xbar.title>`, `<xbar.desc>`, `<xbar.author>`, and
  `<xbar.dependencies>` are what Vee shows about your plugin, and
  `<xbar.dependencies>` is what tells someone why it does not work on their
  machine.

### 2. Submit it to the catalog

Vee's **Discover** window browses the shared
[`matryer/xbar-plugins`](https://github.com/matryer/xbar-plugins) catalog, so a
plugin accepted there reaches xbar, SwiftBar, and Vee users alike.

To propose one for Vee's own catalog and gallery, open an issue using the
**Plugin submission** template in the
[Vee repository](https://github.com/navbytes/vee/issues/new/choose). Include what
the plugin does, its language and dependencies, its declared `<vee.*>`
capabilities, and a link to the source.

Submissions are reviewed against the trust model, and this is the part worth
taking seriously: **declarations must match behavior.** A plugin whose
`<vee.network>` list omits a domain it actually contacts will be declined, because
the whole point of the declaration is that a user can rely on it when deciding
whether to run un-sandboxed code. Declaring more than you use is fine; declaring
less is not. See the [trust model](trust-model.md).

### 3. Run your own store

For internal or team plugins that should not be public, Vee can read a **custom
store** — a GitHub repo, a static HTTP host, or an air-gapped `file://` mirror —
and show it in Discover alongside (or instead of) the public catalog, installing
through the same trust gate.

That is the enterprise path, including private repositories, integrity checks,
and MDM-managed configuration: see
[Custom plugin stores](enterprise-store.md).

### Before you publish, whichever route

- `vee lint` exits non-zero on authoring mistakes — wire it into CI if the plugin
  lives in a repository. See [Debugging and testing plugins](debugging.md).
- Check the plugin degrades gracefully with no token, no network, and a missing
  dependency. A plugin that prints a useful "not configured" row beats one that
  prints a stack trace into someone's menu bar.
- Declare your `<vee.*>` capabilities honestly, even outside the catalog — they
  are what the [trust summary](trust-model.md) shows at install.

## See also

- [Trust model](trust-model.md) — declare what your plugin accesses.
- [Preferences](preferences.md) — declare typed settings and secrets.
- [Writing plugins with an LLM](writing-plugins-with-an-llm.md) — the format in one file, the schemas, and the `vee lint` loop.
- [Custom plugin stores](enterprise-store.md) — host your own catalog of internal plugins.
- [Widgets](widgets.md) — render a plugin on the desktop and in Notification Center.
- [Debugging and testing plugins](debugging.md) — preview, watch, and lint a plugin while you write it.
- [CLI and URL actions](cli-and-urls.md) — trigger refresh/notify from a plugin.
- [Troubleshooting](troubleshooting.md) — when a plugin does not appear or errors.
