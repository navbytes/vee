## Why

A plugin's menu is rendered by two independent code paths that agree only by
convention. `MenuBuilder` emits an `NSMenu` tree for the menu bar;
`MenuFlattener` + `MenuSearchContentView` emit a flat, fuzzy-ranked list for the
detached window and the transient panel. Three separate decisions — whether a
row is actionable, which inline graphic it carries, and whether a submenu
suppresses its own action — are implemented **twice** and kept in sync by
comment. `MenuFlattener.isActionable` literally documents itself as mirroring
`AppActionDispatcher.perform` "exactly"; nothing enforces that. It is correct
today and nothing will report the day it stops being.

The two paths also disagree on shape, not just code: the menu bar shows a tree,
the window shows a flat list with breadcrumbs. The window is the surface a user
leaves open to *watch* a plugin, and it is the one that discards the structure
the plugin authored.

## What Changes

- **Extract a single resolved menu model** (`MenuTree` / `MenuRowSpec`) that owns
  every presentation decision: which nodes become rows, actionable vs. inert,
  submenu-wins-over-action, which accessory a row carries, alternate placement,
  title attributes, and icon. `MenuBuilder` and the new window renderer both
  become dumb emitters over it. Neither decides anything.
- **The detached window and transient panel become hierarchical**, replacing the
  flat breadcrumb list with inline disclosure. Nesting is preserved and
  expandable in place, so two branches can be watched side by side.
- **Search becomes a filter over the tree** rather than a separate flat
  projection: a query prunes to matching rows plus their ancestor chain and
  auto-expands the survivors. **BREAKING** for the surface's behavior — a tree
  cannot reorder, so fuzzy *ranking* no longer applies within a window; results
  keep the plugin's authored order.
- **The window gains the dropdown's controls** — Refresh, Settings, About,
  Reveal in Finder, Edit Plugin, Debug — which are menu-bar-only today. A
  detached window currently offers no way to refresh its own plugin. These are
  chrome, and are excluded from the filter.
- **Disclosure state survives live refreshes.** A window updates on every
  plugin tick; expansion is keyed by path so a refresh does not collapse what
  the user opened.
- **Remove cross-plugin "Search All Plugins"** — **BREAKING**, a shipped
  feature is deleted. Both entry points go (the ⌘F item in the Vee menu and the
  opt-in global hotkey), along with the aggregator, its preferences, and its
  Settings row. It is the only menu surface with no tree to show, and it is not
  wanted.
- The menu bar **keeps `NSMenu`**. Native flyouts, `key=` equivalents,
  `alternate=` modifier-swap, type-select, and menu VoiceOver semantics are
  preserved. Menu-bar and window remain two presentations of one model, not one
  pixel-identical renderer.

Not in scope: the `vee show` / `vee dev` terminal surface, and the WidgetKit
surface beyond sharing leaf gauge/sparkline primitives.

## Capabilities

### New Capabilities

- `menu-surface-model`: the single resolved description of a plugin's menu that
  every presentation consumes — row identity, actionability, accessory
  selection, submenu and alternate structure — such that two renderers cannot
  disagree about what a row means or what activating it does.

### Modified Capabilities

- `detached-plugin-windows`: the window presents its plugin's menu as a
  navigable hierarchy rather than a flat ranked list; search becomes a
  structure-preserving filter; expansion state persists across refreshes; the
  window carries the dropdown's plugin controls.

## Impact

**Code — new/changed**
- `VeeMenu`: new shared model; `MenuBuilder` reduced to an `NSMenu` emitter.
- `VeeApp`: `MenuSearchContentView` → a hierarchical tree view;
  `MenuSearchViewModel` and `DetachedPluginWindowModel` change from
  `[SearchEntry]` to a tree plus expansion state; `DetachedPluginWindows` and
  `MenuSearchPanel` host the new view.
- `VeeUI`: `MenuRowAccessory` and the three AppKit row views
  (`ProgressMenuItemView`, `SparklineMenuItemView`, `CategoryChartMenuItemView`)
  converge on one accessory decision and shared leaf drawing.

**Code — deleted**
- `AppController`: `openSearchAllPanel`, `aggregateSearchRows`,
  `registerSearchAllHotkey`, `applySearchAllHotkey`, and their state (~90 lines).
- `MainMenuController`: the "Search All Plugins…" item and its wiring; ⌘F is
  freed in the Vee menu.
- `AppPreferences`: `searchAllHotkeyEnabled`, `searchAllHotkeyCombo`.
- `VeeUI/GeneralSettingsView`: the search-all hotkey row and its model.
- `VeeSearch`: `SearchEntry`, `flattenEntries`, `normalized`/`collapseSeparators`
  /`dropDanglingHeaders`, and `prefixed(with:)` on both types. The normalization
  pass exists only to repair damage flattening causes; a tree creates none.

**Surviving flat projection**
`MenuFlattener.flatten` / `FlatRow` / `FuzzyScorer` remain, with exactly one
consumer left: the `vee search` CLI subcommand. If the parked terminal-surface
decision later removes that, the flat projection goes with it.

**User-visible**
- Anyone who enabled the Search All Plugins hotkey loses it silently; their key
  combination becomes free. Needs a CHANGELOG entry.
- Two orphaned `UserDefaults` keys (`vee.searchAllHotkeyEnabled`,
  `vee.searchAllHotkeyCombo`) are left in place rather than migrated.

**Docs**
- `ARCHITECTURE.md`: "The menu surface has two presentations" and the
  four-renderers count both change.
- `docs/_content/roadmap.md`: the "search everything" slice is withdrawn.
- `docs-site`: any documentation of ⌘F / Search All Plugins.

**Risk**
Preserving disclosure state across live refreshes is the primary hazard: menu
nodes carry no stable identity, so a plugin that retitles a group on each tick
(`"Disks (3)"` → `"Disks (4)"`) can collapse expansions under the user's hands.
