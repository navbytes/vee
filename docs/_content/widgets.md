---
title: "Widgets"
description: "Render Vee plugins as native desktop and Notification Center widgets: the surface contract, the widget card schema, the five templates, and the composable layout tree."
sidebar:
  label: "Widgets"
  order: 5
head:
  - tag: link
    attrs:
      rel: "alternate"
      type: "text/markdown"
      href: "/guide/widgets.md"
      title: "Markdown source"
  - tag: title
    content: "Widgets — Vee docs"
---
Vee plugins can render on your desktop and in Notification Center as native
WidgetKit tiles, not just in the menu bar. Every plugin already has a widget
representation for free; a plugin that opts in can print a **widget card** — a
JSON payload describing real data — and Vee draws it with native SwiftUI.

This page covers the widget surface contract, the card schema, the five
templates, and the composable layout tree for cards that the templates do not
fit. For the menu-bar output format, see the [Plugin authoring
reference](plugin-authoring.md).

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

## `VEE_TARGET`

Every run gets a `VEE_TARGET` environment variable:

- `VEE_TARGET=menu` — a normal run; print the usual xbar/SwiftBar text (or
  [JSON](json-output.md)).
- `VEE_TARGET=widget` — a widget-mode run; print **one JSON object** (the
  "card", schema below) to stdout and nothing else.

Branch on it like Scriptable's `config.runsInWidget`. If your plugin ignores
`VEE_TARGET=widget` and prints menu text anyway, Vee falls back to scraping
that text — graceful degradation, never a crash.

## The card

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
    { "label": "Orders",  "value": "214", "symbol": "bag",           "tint": "blue",
      "url": "https://dash.example.com/orders" },
    { "label": "Refunds", "value": "3",   "symbol": "arrow.uturn.left", "tint": "red",
      "shortcut": "Review Refunds" }
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
| `items` | [Item]? | Rows for `list`/`board`: `{label, value?, symbol?, tint?, url?, shortcut?}` — see [Tappable rows](#tappable-rows). |
| `actions` | [Action]? | Up to two rendered as buttons — see below. |
| `refresh_after` | int? | Seconds; a hint for the next widget reload. |
| `stale_after` | int? | Seconds; when the tile should show a stale treatment (else the interval-derived default). |
| `layout` | node? | A composable [layout tree](#the-layout-tree). When present, it replaces `template` entirely. |

Unknown top-level keys are ignored (forward-compatible); an invalid value
(bad `progress`, a non-finite `trend` entry, an unsafe `href` URL) degrades to
`nil`/dropped with a diagnostic, visible in the plugin's Debug console —
never a crash.

## Templates

Five native SwiftUI templates, each adapting across the small/medium/large
widget families — describe your data, Vee draws it:

- **stat** — glyph, big `value` in `tint`, `title`/`caption`. The default.
- **gauge** — stat + a native gauge from `progress`.
- **trend** — stat + a sparkline from `trend`.
- **list** — `title` header + `items` as rows, truncated per family (small
  shows the headline `value`; medium ≤3 rows; large ≤8).
- **board** — a compact grid of `items` as stat cells (a KPI board); small
  collapses to the headline.

If none of the five fits your data, skip `template` and send a
[layout tree](#the-layout-tree) instead.

## Tappable rows

A `list` or `board` item can be a **tap target**. Add `url` to open a link, or
`shortcut` to run a named macOS Shortcut:

```json
"items": [
  { "label": "Orders",  "value": "214", "url": "https://dash.example.com/orders" },
  { "label": "Refunds", "value": "3",   "shortcut": "Review Refunds" },
  { "label": "Pending", "value": "12" }
]
```

- `url` — scheme-filtered exactly like an `href` action (`http`/`https`/custom
  app deep links; never `file`/`javascript`/…). A blocked or unparseable URL
  drops the tap with a diagnostic and leaves the row inert, keeping its data.
- `shortcut` — the Shortcut's name, like menu `shortcut=`.
- A row declaring **both** opens its `url` — the same href-before-shortcut
  precedence the menu applies.
- A row declaring **neither** renders inert, exactly as every row did before
  these existed.

There is deliberately **no `shell`** on an item, for the same reason there is no
`shell` action: a widget row must not run an arbitrary command without the
menu's context. The field simply does not exist — declaring one runs nothing and
produces a diagnostic explaining why.

Rows only exist on the medium and large tiles (`small` collapses to the headline
`value`), so tap targets appear there too.

## The layout tree

The five templates cover most tiles. When your data does not fit one — two
columns, a header rail, a KPI grid, a ring over a label — a card can carry a
**layout tree** instead: a small vocabulary of containers and leaves that Vee
walks into native SwiftUI.

A card is **either a template or a tree**. Set `layout` and the `template` field
is not consulted at all.

```json
{
  "vee_widget": 1,
  "layout": {
    "type": "vstack",
    "align": "leading",
    "spacing": 6,
    "children": [
      {
        "type": "hstack",
        "spacing": 5,
        "children": [
          { "type": "image", "symbol": "cpu", "style": { "tint": "blue" } },
          { "type": "text", "text": "CPU",
            "style": { "font": { "size": "caption", "weight": "semibold" }, "tint": "secondary" } },
          { "type": "spacer" }
        ]
      },
      { "type": "text", "text": "38%",
        "style": { "font": { "size": "title", "design": "rounded" }, "tint": "green",
                   "monospaced_digit": true, "min_scale": 0.6 } },
      { "type": "gauge", "value": 0.38, "gauge_style": "circular", "style": { "tint": "green" } },
      { "type": "chart", "kind": "stackedbar", "values": [62, 21, 17],
        "labels": ["User", "System", "Idle"], "colors": ["blue", "orange"],
        "families": ["medium", "large"] }
    ]
  }
}
```

The tree is deliberately **bounded, not freeform**: there is no absolute
positioning, no point frames, and no scroll views. Every node maps 1:1 to a
SwiftUI primitive, which is what keeps the renderer small and keeps this from
turning into the WebView canvas Vee exists to avoid.

### Node types

Every node has a `type`. Containers hold `children`; leaves do not.

| `type` | Kind | Carries | Renders as |
|---|---|---|---|
| `vstack` | container | `children`, `align`, `spacing` | A vertical stack |
| `hstack` | container | `children`, `align`, `spacing` | A horizontal stack |
| `zstack` | container | `children`, `align` | A depth stack — overlays, rings over labels |
| `grid` | container | `children`, `columns`, `spacing` | A grid, left-aligned |
| `text` | leaf | `text` | A text run |
| `image` | leaf | `symbol` | An SF Symbol glyph (v1 renders SF Symbols only) |
| `gauge` | leaf | `value`, `gauge_style` | A native gauge |
| `sparkline` | leaf | `values` | A sparkline |
| `chart` | leaf | `kind`, `values`, `labels`, `colors` | A [share chart](charts.md) — pie, donut, or stacked bar |
| `spacer` | leaf | `min_length` | Flexible space |
| `divider` | leaf | — | A hairline rule |

An unrecognised `type` renders nothing and produces a diagnostic, rather than
failing the card.

### Node fields

| Field | Type | Applies to | Meaning |
|---|---|---|---|
| `type` | string | all | The node kind, from the table above. Required. |
| `text` | string? | `text` | The string to draw. Truncated at **512** characters. |
| `symbol` | string? | `image` | SF Symbol name. |
| `value` | double? | `gauge` | Fill, clamped to `0…1`. |
| `values` | [double]? | `sparkline`, `chart` | A sparkline's series (non-finite entries dropped, capped at **256** points), or a chart's segment magnitudes (non-finite *and negative* entries dropped, folded past **8** segments). |
| `gauge_style` | string? | `gauge` | `linear` (default) or `circular`. |
| `kind` | string? | `chart` | `pie`, `donut`, or `stackedbar`. **Required** — an unrecognised kind drops the leaf with a diagnostic, and the rest of the card still renders. |
| `labels` | [string]? | `chart` | Per-segment names, positional against `values` and allowed to be shorter. Drawn as a legend where the family has room. |
| `colors` | [color]? | `chart` | Per-segment colors, positional and allowed to be shorter — a segment past the end takes its palette slot, so `["blue", "orange"]` recolors only the first two. |
| `align` | string? | containers | Cross-axis alignment — see below. |
| `spacing` | double? | containers | Inter-child spacing in points, clamped `0…64`. |
| `columns` | int? | `grid` | Column count. Default `2`, clamped `1…4`. |
| `min_length` | double? | `spacer` | Minimum space in points, clamped `0…4096`. |
| `families` | [string]? | all | Which widget sizes this node appears in — see [Adapting per widget size](#adapting-per-widget-size-families). |
| `style` | object? | all | Per-element styling — see below. |
| `children` | [node]? | containers | Child nodes. |

`align` takes a different vocabulary per container, matching SwiftUI's own —
anything unrecognised falls back to the default:

| Container | Accepted `align` | Default |
|---|---|---|
| `vstack` | `leading`, `center`, `trailing` | `leading` |
| `hstack` | `top`, `center`, `bottom` | `center` |
| `zstack` | `topLeading`, `top`, `bottom`, `leading`, `trailing`, `center` | `center` |

### `style`

A bounded set of modifiers. Every numeric value is clamped.

| Field | Type | Meaning |
|---|---|---|
| `font` | object? | Text font — see below. |
| `tint` | color? | Named (`green`, `secondary`) or `#rrggbbaa`. |
| `align` | string? | Multiline text alignment: `leading` (default), `center`, `trailing`. |
| `padding` | double? | Uniform padding in points, clamped `0…64`. |
| `line_limit` | int? | Maximum text lines, clamped `1…20`. |
| `monospaced_digit` | bool? | Fixed-width digits — stops numeric columns jittering between refreshes. |
| `min_scale` | double? | Minimum scale factor, clamped `0.3…1.0`. Lets a headline shrink to fit instead of truncating. |
| `fill` | bool? | Grow to fill the available width. This is the *only* width control; arbitrary point frames are deliberately not exposed. |

`style.font`:

| Field | Type | Accepted values |
|---|---|---|
| `size` | string? | `caption2`, `caption`, `footnote`, `subheadline`, `headline`, `title3`, `title2`, `title`, `largeTitle`. Anything else falls back to body. |
| `point_size` | double? | An explicit size, clamped `8…96`. **Wins over `size`** when both are set. |
| `weight` | string? | `medium`, `semibold`, `bold`. Anything else is regular. |
| `design` | string? | `rounded`, `monospaced`, `serif`. Anything else is the default face. |

Use `size` by default — a semantic token scales with the system text size.
Reach for `point_size` only when a token cannot hit what you need, like an
oversized headline number or a very small legend.

### Adapting per widget size (`families`)

A node with `families` renders only in the widget sizes it lists; a node without
it renders in all of them. Values are `small`, `medium`, and `large`.

This lets **one tree adapt by subtraction** rather than making you author three
payloads — the same way the preset templates truncate their rows per size:

```json
{ "type": "text", "text": "214 orders today", "families": ["medium", "large"] }
```

The small tile drops that row; the medium and large tiles keep it.

### Limits

The tree is sanitized before it is rendered. Every limit degrades — truncating,
clamping, or dropping, with a diagnostic in the Debug console — and never fails
the card:

| Limit | Value |
|---|---|
| Maximum nesting depth | 8 levels (deeper children are dropped) |
| Maximum nodes per tree | 64 (extra nodes dropped) |
| Maximum `text` length | 512 characters (truncated) |
| Maximum `sparkline` points | 256 (truncated) |
| Maximum `chart` segments | 8 — the tail is **folded**, not truncated, into a trailing `Other`, so the shares still add up to your own total |

Unknown keys are ignored, so a tree stays forward-compatible.

### Building a tree by hand

There is no builder to import — construct the object directly and print it.
Point `$schema` at the [published schema](#editor-validation-json-schema) for
field-name autocomplete and validation as you write it. This produces exactly
the payload shown at the top of this section:

```json
{
  "$schema": "https://vee.navbytes.io/schemas/widget-card.schema.json",
  "vee_widget": 1,
  "layout": {
    "type": "vstack",
    "align": "leading",
    "spacing": 6,
    "children": [
      {
        "type": "hstack",
        "spacing": 5,
        "children": [
          { "type": "image", "symbol": "cpu", "style": { "tint": "blue" } },
          { "type": "text", "text": "CPU", "style": { "font": { "size": "caption", "weight": "semibold" }, "tint": "secondary" } },
          { "type": "spacer" }
        ]
      },
      { "type": "text", "text": "38%", "style": { "font": { "size": "title", "design": "rounded" }, "tint": "green", "monospaced_digit": true, "min_scale": 0.6 } },
      { "type": "gauge", "value": 0.38, "gauge_style": "circular", "style": { "tint": "green" } },
      { "type": "chart", "kind": "stackedbar", "values": [62, 21, 17], "labels": ["User", "System", "Idle"], "colors": ["blue", "orange"], "families": ["medium", "large"] }
    ]
  }
}
```

Print it with `console.log(JSON.stringify(payload))` / `print(json.dumps(payload))`, whichever language the plugin is written in — see the [runnable `widget-layout` fixture](https://github.com/navbytes/vee/blob/main/plugins/fixtures/widget-layout.txt) for a full example the Swift parser is tested against.

## Actions

Up to two `actions` render as buttons:

- `refresh` — re-runs this plugin.
- `href` — opens a URL (scheme-filtered like menu `href=`: `http`/`https`/
  custom app deep links; never `file`/`javascript`/…).
- `shortcut` — runs a named macOS Shortcut (`name`), like menu `shortcut=`.

There is deliberately **no `shell` action** — a widget button must not run an
arbitrary command without the menu's context. The same exclusion applies to
[tappable rows](#tappable-rows), which carry `url`/`shortcut` and nothing else.

The widget's vocabulary is allowed to lag the menu's, but never silently: every
menu display graphic and action kind has a recorded widget disposition —
supported, or excluded with a reason — in the [surface parity
ledger](https://github.com/navbytes/vee/blob/main/docs/design/surface-parity.md).

## Building the card

Print the object directly — no builder to import:

```ts
if (process.env.VEE_TARGET === "widget") {
  console.log(JSON.stringify({
    vee_widget: 1,
    template: "stat",
    title: "Revenue",
    symbol: "chart.line.uptrend.xyaxis",
    tint: "green",
    value: "$18.2k",
    status: "ok",
    actions: [{ kind: "refresh", label: "Refresh" }],
  }));
} else {
  // ordinary menu-bar output
}
```

```python
if os.environ.get("VEE_TARGET") == "widget":
    print(json.dumps({
        "vee_widget": 1,
        "template": "stat",
        "title": "Revenue",
        "symbol": "chart.line.uptrend.xyaxis",
        "tint": "green",
        "value": "$18.2k",
        "status": "ok",
        "actions": [{"kind": "refresh", "label": "Refresh"}],
    }))
else:
    pass  # ordinary menu-bar output
```

## Editor validation (JSON Schema)

Vee publishes a schema for the card payload, so your editor can check a card
while you write it — unknown fields, bad enum values, out-of-range numbers —
against the same constraints Vee applies at runtime:

<https://vee.navbytes.io/schemas/widget-card.schema.json>

Reference it from a card you are authoring by hand:

```json
{
  "$schema": "https://vee.navbytes.io/schemas/widget-card.schema.json",
  "vee_widget": 1,
  "template": "stat",
  "title": "Revenue"
}
```

`$schema` is an unknown key to Vee, and unknown keys are ignored, so leaving it
in a shipped plugin is harmless.

The schema covers every field the parser reads, including the layout tree, and
CI validates it against the shipped fixtures — so it cannot quietly drift from
what Vee accepts.

## See also

- [Plugin authoring reference](plugin-authoring.md) — the menu-bar output format.
- [JSON output format](json-output.md) — the structured alternative for menu output.
- [Getting started](getting-started.md#widgets-on-your-desktop--notification-center) — adding a widget to your desktop.
- [Debugging and testing plugins](debugging.md) — previewing a plugin's output while you write it.
