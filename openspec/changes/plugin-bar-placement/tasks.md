# Tasks: plugin-bar-placement

Each task carries the checks that decide it is done. Gate on
`swift build && swift test && swiftlint lint --strict`.

## 1. The placement value and its storage

- [ ] 1.1 Add `Sources/VeePreferences/BarPlacement.swift`: the enum from
  design.md §2, with `encoded`/`init?(encoded:)` round-tripping
  `own` / `folded:Vee` / `hidden`.
  - Unknown or malformed encodings decode to `nil` so the caller falls back to
    the default rather than inventing a placement
  - Round-trip unit tests for all three cases plus a garbage string
- [ ] 1.2 `AppPreferences`: `defaultPlacement` derived from the existing
  `compactMenuBar` key (`true` → `.foldedDefault`, `false` → `.own`), a
  per-plugin override map storing only departures from the default, and
  `placement(_ id:)` / `setPlacement(_:id:)` / `placementIDs()`.
  - `setPlacement(nil, id:)` clears the override so the plugin follows the
    default again
  - An install with `compactMenuBar == true` and no overrides resolves every
    plugin to folded; with it `false`, to `own` — the migration check
  - Changing `defaultPlacement` moves only plugins with no override
- [ ] 1.3 Extend `clearAllState(id:)` to clear placement, and include
  `placementIDs()` in `AppController.reconcileDiskState`'s candidate set, so a
  deleted plugin's placement is collected like its other state.
  - Test in `Tests/VeePreferencesTests`: set a placement, clear all state, the
    plugin resolves to the default again
- [ ] 1.4 Rename `compactMenuBarDidChangeNotification` to
  `barPlacementDidChangeNotification`, posted from both the default setter and
  the per-plugin setter. Still payload-free — observers re-read.

## 2. `StatusItemController` over three placements

- [ ] 2.1 Add the `pluginID: String` init parameter (design.md §5) and pass it
  from `PluginCoordinator` alongside the existing `autosaveName`.
- [ ] 2.2 Replace the `isCompact` flag with a resolved `BarPlacement`, and
  `reconcileMode()` with `reconcilePlacement()` handling every transition
  through two helpers — `attachOwnItem()` / `attachFoldedRow()` — and one
  `detachBarSurface()`.
  - Every ordered pair of distinct placements switches without losing the
    plugin's last render (`repaintCurrentSurface()` still runs)
  - Switching twice in a row is idempotent and leaks no status item or row
- [ ] 2.3 Add the no-bar-surface branch to `applyPresentation`, `applyMenu`,
  `applyTitleText` and `applyAlpha`: with both surfaces nil they store state
  and paint nothing.
  - A hidden plugin's `render(_:)` still stores `lastRendered`, still calls
    `DetachedPluginWindows.update`/`markFresh`, still publishes its widget
    scrape
  - `renderError` on a hidden plugin still calls
    `DetachedPluginWindows.markStale`
  - Un-hiding paints the stored render immediately, not at the next refresh
- [ ] 2.4 Guard the shared item's error roll-up so it only tracks folded rows,
  and clear a plugin's membership when it leaves the folded placement.
  - A plugin erroring while folded, then pinned or hidden, does not leave the
    home item's warning glyph stuck on

## 3. One Vee home item

- [ ] 3.1 Rename `CompactMenuBarController` → `VeeHomeItemController` (file,
  type, `Tests/VeeAppTests/CompactMenuBarControllerTests.swift`), keeping the
  `attachesStatusItem: false` test seam exactly as it is.
- [ ] 3.2 Make the item permanent: the app-controls footer is installed once at
  setup, `installFooter`/`removeFooter` collapse into that, and `deactivate()`
  is deleted.
  - The item exists with zero plugin rows, and its rows match
    `MainMenuController.buildAppItems` exactly (the existing seam test)
  - The footer's leading separator stays hidden when there are no rows above it
- [ ] 3.3 `MainMenuController` stops creating an `NSStatusItem`; it remains the
  builder and `@objc` target for the app-control rows. Delete `setVisible`,
  `isVisible`, `remove()`, and `AppController.applyCompactMode` with its
  notification observer.
  - `MainMenuControllerTests` still exercises the rows and their callbacks
  - Exactly one Vee item exists in every placement combination, including all
    plugins hidden

## 4. Coordinator wiring

- [ ] 4.1 `PluginCoordinator` resolves the plugin's placement at construction
  and observes `barPlacementDidChangeNotification` (the observer already exists
  in `StatusItemController`; confirm it re-reads per plugin, not globally).
  - A placement change for plugin A does not repaint or disturb plugin B, and
    never closes an open sibling submenu
- [ ] 4.2 Confirm `<vee.surface>widget` plugins are untouched: still no
  controller, still no menu-mode schedule, and placement is not offered for
  them in the UI.

## 5. User interface

- [ ] 5.1 `GeneralSettingsView`: the Menu Bar section becomes a
  default-placement choice (own item / combined), keeping the existing
  explanatory footer. Same live-apply behaviour as the current toggle.
- [ ] 5.2 Plugin Manager rows: a per-plugin placement control (own / folded /
  hidden) plus "Use default", and the per-plugin actions that keep a hidden
  plugin reachable — refresh, open in window, settings, debug, reveal, edit —
  driven by the coordinator closures (design.md §8).
  - Every action works for a plugin with no menu-bar item
- [ ] 5.3 Choosing `hidden` offers the surfaces that replace it — open in a
  window, bind a hotkey — dismissible, and never blocking the placement change.

## 6. Docs

- [ ] 6.1 Docs site: the menu-bar section documents the three placements and
  states plainly that placement is the user's and `<vee.surface>` is the
  author's.
- [ ] 6.2 Amend `openspec/specs/detached-plugin-windows/spec.md`'s "Opening a
  plugin in a window" requirement: the action is guaranteed *available for
  every plugin*, with the dropdown as one route rather than the guarantee, and
  add a scenario for opening a window for a plugin with no menu-bar item.
- [ ] 6.3 `docs/design/roadmap.md`: mark the plugin-grouping model and the
  lightweight status-item hide as delivered under the Focus-filters entry, and
  note what Focus filters still need (the plugin `AppEntity` picker).

## 7. Verify

- [ ] 7.1 `swift build && swift test && swiftlint lint --strict`.
- [ ] 7.2 Manual QA at the GUI, which the unit tests cannot reach: a plugin
  moved through all three placements while running; an upgrade from each value
  of the old toggle; a hidden plugin's detached window updating and going
  stale; a hidden plugin's hotkey; the round trip returning a pinned item to
  its previous slot.
