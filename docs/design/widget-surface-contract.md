# Design: the widget surface contract

Status: **implemented** (single-card; timeline arrays deferred — see
"Deferred" below). Supersedes the "Follow-ups (Tier 3)" section of
[`widgets.md`](widgets.md), which shipped the Tier-0/Tier-1 mirror. This document
specifies making widgets a *first-class output surface* of a plugin rather than a
scrape of its menu-bar line.

## Problem

Today the widget is derived from the menu bar. `PluginCoordinator.widgetFields`
scrapes the title line (text, `color=`, `sfimage=`) plus whatever
`progress=`/`sparkline=` happens to sit on the first row, and the extension
renders that. It is strictly *less* than the menu bar it mirrors, for a structural
reason: **the xbar/SwiftBar protocol is a rendering language for a 20‑pixel strip,
and a widget wants data.** A menu title is a string tuned for the menu bar
(`"⚠︎ 3 ▲$182"`); a widget wants `{value: "$182", trend: […], status: warning}`
so *Vee* can lay it out per size class, in dark mode, on the lock screen, with real
typography and tappable actions. Scraping a render target back into data yields a
caricature.

Three mismatches follow:

1. **Semantics** — the menu line is presentation, not structured content.
2. **Cadence** — menu plugins run as often as every 5s; WidgetKit grants a
   frequently-viewed widget only ~40–70 reloads/day (≈ every 15–60 min, dynamically
   budgeted). The widget should not be a byproduct of the menu's schedule.
3. **Interaction** — widgets act through `AppIntent` buttons, not menu-row clicks.
   None of `shell=`/`href=`/`refresh=` map onto a widget today.

## Prior art (what the incumbents do)

- **Scriptable** (iOS/macOS, the closest analog — native, no WebView). One script
  serves both surfaces and branches on `config.runsInWidget`; it *describes* a
  widget by building a tree of primitives (`ListWidget` + stacks/text/image/gauge),
  and the app renders it natively. It has **no separate "widget plugin" class** —
  same script, runtime flag. It hints the next reload via `refreshAfterDate`.
- **Übersicht** — shell command → **HTML/CSS/JSX/React** drawn on the desktop. Max
  flexibility, but it's a WebView model (exactly what Vee rejects for
  leak-freedom), desktop-only (no WidgetKit / Notification Center / lock screen),
  and each widget is a separate `.jsx` file — the "separate class" model, in a
  standalone app.
- **SwiftBar / xbar** — our direct ancestors — have **no native widget support at
  all**. Menu bar only.
- **Native WidgetKit apps** (iStat Menus, One Thing) ship fixed, hand-built widgets
  with no plugin model — the polish bar, but not extensible.

Takeaway: the one app built like Vee (native, no WebView) uses *same plugin +
runtime mode + describe-don't-draw*. The one that went *separate class* did it with
the WebView Vee exists to avoid. So the right shape is a **contract, not a class.**

## Decision

Add a **widget output surface** to the existing plugin, reached the same way
Scriptable reaches it: a runtime mode flag. Same file, same folder, same trust
model, same `<xbar.var>` preferences, same Keychain secrets, same discovery, same
SDKs. What the user's "separate class for widgets" instinct actually wants —
a plugin with no menu-bar presence that exists only to feed a widget — becomes a
one-line declaration (`<vee.surface>widget</vee.surface>`), not a second species.

### Why not `VEE_WIDGET_FAMILY` (a deliberate divergence from Scriptable)

Scriptable's extension runs the JS *in-process, per placed widget*, so it knows the
family. **Vee's architecture is fundamentally different**: the app runs plugins
out-of-process and writes one shared snapshot file that the sandboxed extension
reads and renders — the extension cannot exec a plugin (that is the whole reason
the snapshot channel exists). One plugin run therefore feeds small, medium, and
large simultaneously. So a plugin cannot be told "which family" at run time, and
**size adaptation lives in the renderer**: the plugin emits one rich payload
(e.g. up to 8 items) and each native template takes what fits (small = headline,
medium = 3 rows, large = 8) — exactly how the current mirror's `listLimit` already
works. This is simpler than Scriptable's model and is the correct fit for a
shared-snapshot, out-of-process producer.

## The contract

### 1. Surfaces — `<vee.surface>`

```
<vee.surface>menu</vee.surface>     # default (absent = menu): today's behavior
<vee.surface>both</vee.surface>     # menu item AND a rich widget tile
<vee.surface>widget</vee.surface>   # NO status item — widget-only plugin
```

- `menu` / absent → unchanged. The widget tile (if the plugin is shown in one) is
  the **Tier-0 scrape**, exactly as today. Nothing regresses; every plugin still
  *has* a widget representation.
- `both` → served in the menu normally, **and** invoked a second time in widget
  mode on the widget interval to produce a rich card.
- `widget` → no `NSStatusItem`, no menu; invoked only in widget mode on the widget
  interval. The "widget-only plugin."

### 2. Cadence — `<vee.widget.interval>`

```
<vee.widget.interval>15m</vee.widget.interval>
```

The widget-mode refresh cadence, parsed with the existing `RefreshInterval` grammar
(`ms`/`s`/`m`/`h`/`d`). Defaults to the plugin's filename interval. **Floored at 5
minutes** regardless of what's requested — WidgetKit's reload budget makes anything
faster meaningless, and a widget-only plugin has no filename interval to inherit.
Independent of the menu interval, so a `cpu.5s.sh` can feed a 5‑second menu and a
15‑minute widget from one file.

### 3. Mode flag — `VEE_TARGET`

Every plugin run gets `VEE_TARGET` in its environment (injected by
`EnvironmentBuilder`):

- `VEE_TARGET=menu` — a normal run; print the xbar/SwiftBar text (or JSON) format.
- `VEE_TARGET=widget` — a widget-mode run; print **one JSON card object** (schema
  below) to stdout and nothing else.

A plugin branches on it exactly like Scriptable's `config.runsInWidget`. A plugin
that ignores it and prints menu text in widget mode simply falls back to the
Tier‑0 scrape of that text (graceful degradation).

### 4. The card payload (widget-mode stdout)

A single JSON object. Unknown keys are ignored (forward-compatible); invalid values
degrade to nil with a parse diagnostic (surfaced in the Debug console), never a
crash.

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
    { "label": "Orders",  "value": "214", "symbol": "bag",           "tint": "blue"  },
    { "label": "Refunds", "value": "3",   "symbol": "arrow.uturn.left", "tint": "red" }
  ],

  "actions": [
    { "label": "Refresh", "kind": "refresh" },
    { "label": "Open",    "kind": "href",     "url": "https://dash.example.com" },
    { "label": "Deploy",  "kind": "shortcut", "name": "Deploy Prod" }
  ],

  "refresh_after": 900,
  "stale_after": 3600
}
```

| field | type | meaning |
|---|---|---|
| `vee_widget` | int | payload schema version (currently `1`); guards forward evolution |
| `template` | enum | `stat` \| `gauge` \| `trend` \| `list` \| `board` (see §5). Unknown → `stat` + diagnostic |
| `title` | string | tile heading (the plugin/metric name) |
| `symbol` | string? | SF Symbol name for the glyph |
| `tint` | color? | named (`green`) or `#rrggbbaa`; reuses `SnapshotColor` parsing |
| `value` | string? | the headline value, already formatted by the plugin |
| `caption` | string? | small secondary line (e.g. "today", "since 9am") |
| `detail` | string? | one more line of context |
| `status` | enum? | `ok` \| `warning` \| `error` — drives styling + the health roll-up |
| `progress` | double? | `0…1`, clamped; the `gauge` template's fill |
| `trend` | [double]? | the `trend` template's series |
| `items` | [Item]? | rows for `list`/`board`; `{label, value?, symbol?, tint?}` |
| `actions` | [Action]? | up to 2 rendered as buttons (§6) |
| `refresh_after` | int? | seconds; a hint for the next widget reload (like `refreshAfterDate`) |
| `stale_after` | int? | seconds; when the tile should show a stale treatment (else the interval-derived default) |

The plugin emits the *richest* payload it has; each template/family renders the
subset that fits.

### 5. Templates (native SwiftUI, in the extension)

Five templates, each a native view adapting across `small`/`medium`/`large`:

- **stat** — glyph, big `value` in `tint`, `title`/`caption`. The default.
- **gauge** — stat + a native `Gauge` from `progress`.
- **trend** — stat + the dependency-free `Sparkline` from `trend`.
- **list** — `title` header + `items` as rows (glyph · label · value), truncated per
  family (small shows the headline `value`; medium ≤3; large ≤8).
- **board** — a compact grid of `items` as stat cells (KPI board); small collapses
  to the headline.

Templates are a deliberately small, curated set — **describe, don't draw.** We do
*not* expose freeform drawing (that is Übersicht's WebView path, which conflicts
with leak-freedom and WidgetKit's constraints). New templates are added centrally
as the need proves out.

### 6. Actions (`AppIntent` buttons)

Up to two `actions` render as buttons (macOS 26 interactive widgets). Kinds:

- `refresh` — re-runs *this* plugin. Requires a **per-plugin request channel**:
  generalize the existing refresh-all Darwin notification to carry a plugin id (a
  small request written to the shared support dir + a Darwin notify the running app
  observes; if the app isn't running, the intent launches it). This is the Tier‑3
  "per-plugin request channel" follow-up, now in scope.
- `href` — opens a URL, scheme-filtered exactly like menu `href=`
  (`http`/`https`/custom app deep links; never `file`/`javascript`/…).
- `shortcut` — runs a named macOS Shortcut, like menu `shortcut=`.
- Deliberately **no `shell`** from a widget — a widget button must not run an
  arbitrary command without the menu's context; keep the attack surface small.

### Progressive-enhancement ladder (summary)

| Tier | Author does | Result |
|---|---|---|
| 0 | nothing | scraped tile from the menu line (today) |
| 1 | `<vee.surface>both</vee.surface>` + emit a card on `VEE_TARGET=widget` | rich native tile, own cadence |
| 2 | `<vee.surface>widget</vee.surface>` | widget-only plugin, no menu presence |

## Snapshot v3 (`VeeWidgetShared`)

`PluginSnapshot` gains one optional field: `card: WidgetCard?`. `WidgetCard`,
`WidgetCardItem`, `WidgetCardAction`, and the template/status enums are new
Foundation-only `Codable` types in `VeeWidgetShared` (shared by the app and the
sandboxed extension; still zero-dependency). `WidgetSnapshot.currentVersion` → `3`;
every new field is optional so a v2/v1 file still decodes. When `card` is present
the renderer uses the template; when absent it falls back to the scraped fields
(Tier 0). `failed`/`isStale`/roll-up account for `card.status` when present.

## Runtime & scheduling (`VeeApp` / `VeeRuntime`)

- `EnvironmentBuilder` injects `VEE_TARGET`. `PluginContext` carries the target.
- `PluginCoordinator`: for `surface ∈ {both, widget}`, a second scheduler
  (`RefreshTimer`/cron on the widget interval) invokes the plugin with
  `VEE_TARGET=widget`, parses stdout via `WidgetCardParser`, and hands a
  `WidgetPublish` carrying the card to `WidgetSnapshotPublisher`. A `widget`-surface
  plugin builds **no** `StatusItemController` at all.
- `WidgetPublish`/`WidgetSnapshotPublisher` extend to carry an optional card; the
  content-signature dedupe includes it, so a changed card spends a (throttled)
  reload and an unchanged one doesn't — reusing all the existing metering.
- The `<vee.widget.interval>` floor and the existing 5‑minute reload floor keep the
  extra runs cheap.

## Security & trust

- A widget-only plugin is still un-sandboxed code — it flows through the **same**
  trust gate, `<vee.*>` declarations, and install confirmation as any plugin.
  Nothing about "widget" weakens the model.
- `href` actions are scheme-filtered; `shell` actions are not offered to widgets.
- The card payload is data the app parses; it never drives code execution. The
  snapshot file stays `0600`.

## SDK

Add `Widget`/`Card`/`Stat`/`Gauge`/`Trend`/`List`/`Board` builders to the TS SDK
(the reference), emitting the card JSON with quoting/escaping handled, plus a golden
fixture round-tripped through the Swift `WidgetCardParser`. Python and Go mirror it
(byte-identical fixtures), as a fast follow to keep the three-SDK symmetry.

## What is testable vs compile-only (CI reality)

`WidgetExtension` is **not** an SPM target — only the `app` xcodebuild CI job
compiles it, and it can't be unit-tested. So:

- **Unit-testable (TDD, `swift test`):** the card model + `WidgetCardParser`, the
  header tags, snapshot v3 decode, the mode-flag env injection, the publish/dedupe
  path, the per-plugin refresh-request encoding, and the SDK (npm/pytest/go).
- **Compile-only (xcodebuild):** the SwiftUI template views and the `AppIntent`
  button wiring. Covered by careful review + reuse of the existing
  `WidgetPresentation` helpers, not unit tests.

## Implementation phases (each a TDD wave, one commit)

- **A. Card model + parser** (`VeeWidgetShared` types, `WidgetCardParser` in
  `VeePluginFormat`) — pure, fully tested.
- **B. Header tags** — `<vee.surface>`, `<vee.widget.interval>` into
  `HeaderMetadata`/`HeaderParser`, tested.
- **C. Snapshot v3** — `card` field, version bump, versioned-decode tests.
- **D. Widget-mode invocation + scheduling** — `VEE_TARGET`, second scheduler,
  publish path; widget-only plugins skip the status item.
- **E. Per-plugin refresh channel + intents** — request encoding (tested) +
  `RefreshPluginIntent`/`RunPluginActionIntent` (extension, compile-only).
- **F. Templates** — the five SwiftUI views + action buttons (compile-only).
- **G. SDK** — TS builders + fixtures (Python/Go fast-follow).
- **H. Docs** — supersede this doc's status, update plugin-authoring /
  getting-started / `CHANGELOG` / `ARCHITECTURE`.

Phases A–C are independent and pure; D depends on A–C; E/F depend on A/C; G depends
on A; H last. Each pushes on its own so CI compiles it incrementally.

## Layout tree (composable escape hatch)

Status: **implemented** (v1; images deferred — see below). The five templates
in §5 are ergonomic presets, but a fixed record can't express a two-column
layout, a calendar date rail, activity rings, or a KPI grid. So a card may
instead carry a **`layout`** — a bounded tree of native primitives Vee walks
into SwiftUI. A card is *either* a preset template *or* a tree; presets are
unchanged, so nothing regresses.

This is Scriptable's *describe, don't draw* — a native primitive tree, not a
WebView — but with Vee's out-of-process twist: the app builds the tree, and the
sandboxed extension only renders it. It is deliberately **bounded**, never
freeform: a small vocabulary that each map 1:1 to a SwiftUI primitive.

- **Containers:** `vstack`, `hstack`, `zstack`, `grid` (`columns`, default 2).
  `hstack` is the load-bearing addition — side-by-side regions the presets
  can't do (two columns, a date rail, a row of cells, inline per-row gauges).
- **Leaves:** `text`, `image` (SF Symbol only in v1), `gauge` (`linear` |
  `circular`), `sparkline`, `spacer`, `divider`.
- **Per-element `style`:** `font` (`size` token or bounded `point_size`,
  `weight`, `design`), `tint`, `align`, `padding`, `line_limit`,
  `monospaced_digit`, `min_scale`, `fill`. The last two exist so the presets'
  own value text (`monospacedDigit()` + `minimumScaleFactor(0.6)`) desugars
  faithfully. No absolute positioning, no point frames, no scroll views — that
  boundary is what keeps a tree from becoming the freeform canvas Vee rejects.
- **Family adaptation by subtraction:** each node may carry a `families`
  allow-list (`small`/`medium`/`large`); the walker skips nodes not for the
  current family, so one tree adapts without authoring three payloads (mirrors
  how the presets truncate per family).

All five presets re-express in this vocabulary — `stat`/`gauge`/`trend`/`list`
desugar directly, and `board` is why `grid` is in v1 rather than a later add.
Presets stay on the wire regardless (compatibility + ergonomics); the tree is
the escape hatch, not a replacement. The `actions` footer stays renderer-owned
chrome appended around any tree, so the interactive/trust surface is unchanged.

**Safety — caps live at parse time.** The snapshot the sandboxed extension
re-reads on every timeline build must already be bounded, so `WidgetCardParser`
(app-side) sanitizes the tree on decode, not the walker: depth ≤ 8, ≤ 64 total
nodes, text ≤ 512 chars, sparkline ≤ 256 points, `gauge`/style numerics
clamped, non-finite values dropped, and an unknown node `type` degraded to a
diagnostic. A hostile payload degrades to a bounded tree plus diagnostics —
never a throw (Foundation's own ~512-level decode limit is the backstop for a
pure-depth bomb, and the existing 8 MB stdout drain bounds total payload size).

**SDKs.** All three gain namespaced `Node.*` builders (`Node.VStack`,
`Node.Text`, `Node.Gauge`, …) — namespaced so they don't collide with the
card-level template builders (`Stat`/`Gauge`/…). The `widget-layout` example is
a golden fixture, byte-identical across TS/Python/Go and round-tripped through
`WidgetCardParser` (`FixtureRoundTripTests`).

**Deferred to v2 — `image` bitmaps.** v1 renders SF Symbols by name only. Real
images (now-playing artwork, avatars, map/photo backgrounds) are the one
primitive that stresses the channel: they must *not* be base64-inlined into the
hot snapshot JSON. The plan is for the app (never the extension — remote fetch
belongs un-sandboxed) to fetch/decode and cache images under
`~/Library/Application Support/Vee/`, with the tree referencing them by
content-hash filename; the extension's existing read-only home-relative
entitlement already covers that directory, so images cost zero new sandbox
surface. Separable, hence deferred.

## Deferred (not in the first PR)

- **Timeline arrays** — a card carrying an array of dated entries ("next 5
  meetings") handed to WidgetKit as a real timeline, updating all day on zero extra
  runs. The single most WidgetKit-native capability no menu scraper can express;
  worth a follow-up once the single-card contract lands.
- **Layout-tree images** — bitmap `image` nodes via the app-side cache-and-
  reference scheme described under "Layout tree" above (v1 is SF Symbols only).
- Focus filters (`SetFocusFilterIntent`), lock-screen accessory families, an
  `AppIntent`-configurable Control Center control for a chosen plugin.

## Open questions (resolved)

1. `board` template on `small` — collapse to headline, or drop the template
   for that family? **Resolved: collapse** (`WidgetExtension/WidgetCardView.swift`,
   `BoardCardView`).
2. Should `both`/`widget` plugins that never emit a card on `VEE_TARGET=widget`
   (misbehaving) fall back to the scrape silently, or surface a Debug
   diagnostic? **Resolved: both** — `PluginCoordinator.refreshWidget()` falls
   back to the Tier-0 scrape and logs the `WidgetCardParser` diagnostic.
3. SDK scope for the first PR — TS only, or all three at once? **Resolved: all
   three** — porting the builder to Python and Go turned out straightforward,
   so `plugins/python/vee.py` and `plugins/go/vee.go` shipped alongside the TS
   SDK rather than as a follow-up.
