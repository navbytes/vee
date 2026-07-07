# Design: useful widgets

Status: implemented (Tier 1 + health + freshness). Tier 3 items below are
tracked as follow-ups.

## Problem

The original `PluginStatusWidget` was a `StaticConfiguration` that rendered a
truncated, alphabetical list of `name → title` rows — the **same strings already
in the always-visible menu bar**, shown somewhere you look at less often (the
desktop, or a deliberate Notification Center swipe). It therefore offered
strictly *less* than the thing it mirrored, and it:

- couldn't be told **which** plugins to show (every instance showed all, name-sorted);
- threw away all the presentation the app already computes — color, SF Symbols,
  `progress=` gauges, `sparkline=` series, error state — flattening each plugin
  to one monospaced string;
- hid **freshness**, despite WidgetKit reloads being throttled to ~5 min, so it
  could silently show stale values;
- treated every widget family as "the list, just shorter."

The Control Center **Refresh Vee** control was already good and is unchanged.

## Principle

A widget must offer what the always-visible menu bar cannot: a **bigger/prettier
single-metric tile**, an **aggregate view**, or a **tap target**. Everything
below follows from that.

## Design

### Snapshot v2 (`VeeWidgetShared`)

`PluginSnapshot` gained optional, presentation-carrying fields — `color`,
`symbolName`, `symbolColors`, `progress`, `sparkline`, `isError`, `interval` —
plus helpers (`failed`, `isStale(asOf:)`) and roll-up accessors on
`WidgetSnapshot` (`okCount`, `failingCount`, `failing`). All new fields are
optional so a v1 file still decodes; `WidgetSnapshot.currentVersion` is bumped to
`2`. Colors are a Foundation-only `SnapshotColor` (mirroring `VeeColor`) so the
module stays dependency-free for the sandboxed extension; it encodes to a compact
string (`"red"` / `"#rrggbbaa"`). The app maps `VeeColor → SnapshotColor` at
publish time (`WidgetSnapshotMapping`).

### Enriched publishing (`VeeApp`)

`PluginCoordinator.widgetFields(from:)` distills a `ParsedOutput` into the fields
above: colors and the SF Symbol come from the title line; a `progress=` /
`sparkline=` may instead sit on the first dropdown item (the common "headline row
is the gauge" idiom), so it falls back to it. `onPublish` now hands back a
`WidgetPublish` (title + fields + error flag) instead of a bare string. The
change-detection that skips no-op writes/reloads now compares the **full**
content (timestamps normalized away), so a color/gauge change flushes even when
the title text is unchanged.

### Widgets (`WidgetExtension`)

- **Vee Plugins** — `AppIntentConfiguration` with a `PluginEntity` / `EntityQuery`
  so each instance picks its plugins (the query reads the snapshot, so the picker
  lists exactly what's running; empty selection = all). Per family:
  - **small** = a hero tile: glyph, big colored value, native gauge/sparkline, freshness;
  - **medium/large** = enriched rows (glyph + colored value + inline gauge + freshness).
- **Vee Health** — a `StaticConfiguration` roll-up: "All healthy" / "N failing"
  with the failing plugins listed. This is the view the menu bar structurally
  can't provide.

Freshness uses a self-updating relative label (no extra reloads); `isStale`
floors at 5 min so we never blame WidgetKit's own refresh budget. A sparkline is
a dependency-free `Shape` (no Charts import) for predictable rendering.

## Constraints honored

- **Reload budget.** WidgetKit meters background reloads; the app keeps the 5-min
  reload floor and 30-min fallback timeline. Widgets suit **slow-moving state**
  (disk, battery, weather, build/sync status) — fast per-second values (net
  throughput) still belong only in the menu bar.
- **Sandbox.** `VeeWidgetShared` stays Foundation-only; the extension reads the
  snapshot via the existing read-only home-relative entitlement.

## Follow-ups (Tier 3, not in this change)

- Interactive rows via `AppIntent` buttons: refresh one plugin, or run its
  primary action (needs a per-plugin request channel, generalizing the
  refresh-all Darwin notification).
- Deep-link taps into the app focused on a plugin (via the `vee://` scheme).
- A few dropdown lines in the snapshot for medium/large ("title + top items").
- Focus filters (`SetFocusFilterIntent`) to scope widgets per Focus.
- An `AppIntent`-configurable Control Center control for a chosen plugin.
