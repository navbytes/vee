## Why

A plugin's output is only visible while you hold its dropdown open, or for the
few seconds its search panel is up. Everything Vee renders richly — `progress=`
gauges, `sparkline=`, the `pie=`/`donut=`/`stackedbar=` family, `toggle=`/
`slider=` controls — disappears on the next click. That is the wrong shape for
the case those features exist to serve: watching a value change while you work
in another app.

Vee's only desktop-resident surface today is the WidgetKit widget, and it can't
close this gap. It floors refresh at 5 minutes, it is mandatorily sandboxed, it
requires the plugin to opt in with `<vee.surface>` and emit a separate card
schema, and it offers no interaction beyond App Intents. So a 1-second sparkline
can never be a widget, and a plugin that hasn't opted in can never be on the
desktop at all.

A detached plugin window is the widget you can't have: **any plugin, no opt-in,
the plugin's own refresh cadence, and every action the menu can fire.**

## What Changes

The search panel already renders a plugin's whole menu structure in SwiftUI,
dispatches every action through the real handler, and knows how to be key in an
accessory app. It is transient because nothing has needed it to be otherwise.
This change gives that one surface a second presentation — a persistent window —
rather than building a parallel renderer beside it.

- The existing search panel gains a **window presentation**: titled, resizable,
  movable, and persistent, showing the same content it shows today plus the rich
  rows it currently omits.
- A plugin's dropdown gains an **"Open in Window"** row in its footer (beside
  Refresh / Settings / Debug) that opens it directly in that presentation.
- The transient panel gains a **"keep open"** control that promotes the panel
  you already have in front of you into a window.
- In window presentation the content is **live**, updating on the plugin's own
  refresh cadence. The transient panel keeps its frozen-at-open snapshot, so a
  list never reorders under the cursor mid-search.
- The plugin's **menu-bar item stays** while a window is open. The window is an
  additional view of the plugin, not a relocation of it.
- **One window per plugin**, several plugins at once. Re-invoking focuses the
  existing window rather than opening a duplicate.
- Each window carries a **pin control** switching it between floating above other
  apps and behaving as a normal window. Floating is the default.
- A **"Detached Windows"** submenu in the Vee menu lists every open window and
  brings one to the front. This is the primary retrieval path: Vee is an
  accessory app, so a covered non-floating window has no Dock icon and no
  App Exposé route back.
- A plugin's existing hotkey (`<vee.shortcut>`) gains a choice of **which
  presentation it opens** — transient panel, as today, or window. Because both
  presentations are the same surface, the window carries the search field too,
  so this choice gives nothing up.
- When a plugin is disabled, removed, or starts failing, its window keeps the
  last output on screen and **says it is stale** rather than silently freezing.
- Windows are **session-scoped**. They do not survive quitting Vee.
- The window renders the rich row family at full fidelity and explicitly declines
  the menu-only mechanics — `⌥` alternates and `key=` equivalents.

Non-goals, recorded so they are not re-proposed: persistence across launches,
a desktop/wallpaper-level window layer (WidgetKit already owns that placement),
one shared window with a plugin switcher (it would defeat watching two plugins
side by side), and a second renderer for the menu tree.

## Capabilities

### New Capabilities
- `detached-plugin-windows`: opening a plugin's menu surface as a persistent
  desktop window, keeping it live across refreshes, its window-level and
  retrieval behavior, and the fidelity boundary against the native `NSMenu`.

### Modified Capabilities

_None._ `openspec/specs/` is currently empty; this change introduces the first
capability rather than altering an existing one. The search panel's existing
transient behavior is preserved exactly and gains a presentation alongside it.

## Impact

**Modified**

- `VeeApp/MenuSearchPanel.swift` — a window presentation beside the existing
  transient panel, and a manager for one window per plugin.
- `VeeApp/MenuSearchViewModel.swift` — accept refreshed entries in window
  presentation; keep the frozen snapshot in the transient one.
- The panel's SwiftUI row view — the rich row family (`progress=`, `sparkline=`,
  the chart family, `toggle=`, `slider=`), which it currently omits.
- `VeeApp/StatusItemController.swift` — the "Open in Window" footer row, and the
  liveness feed: `render` is the one place fresh output reaches the UI, so it is
  the one place windows can be kept live.
- `VeeApp/MainMenuController.swift` — the "Detached Windows" submenu, added to
  `buildAppItems`, the single seam both the standalone item and compact mode's
  footer build from.
- `VeeApp/PluginCoordinator.swift` — mark windows stale on teardown, and the
  one-line change to which presentation the plugin's hotkey opens.
- The per-plugin Settings form — a control choosing that presentation.

**Reused unchanged**

- The whole search stack: `VeeSearch`, `MenuFlattener`, `MenuSearch`,
  `SearchEntry`/`FlatRow`, and the panel's keyboard navigation.
- `KeyablePanel` (becoming key as an accessory app) and `FrontmostAppRestorer`
  (returning focus so a plugin's action lands in the right app).
- `AppActionDispatcher` — the panel already dispatches through it, so every
  action and the control re-invocation path work with no change.
- `VeeUI`'s `SparklineChartView`, `CategoryChartView`, `PluginControlView`, built
  for popovers and reusable as rows; `SymbolImageFactory`; `ProgressBarLayout`.
- The entire global-hotkey stack — `HotKeySpec`, `EffectiveHotkey`,
  `HotkeyStatus`, `GlobalHotKeys` (which already takes an arbitrary action), the
  per-plugin disable/rebind preferences, the collision reporting, and the trust
  disclosure. Only which presentation the hotkey opens is new. No new header tag,
  so the plugin format, its documentation, and the three SDKs are untouched.

**Not affected**

The runtime, the parser, the trust layer, the catalog, and the widget channel are
untouched. No new dependencies — the project ships zero third-party code and this
adds none.
