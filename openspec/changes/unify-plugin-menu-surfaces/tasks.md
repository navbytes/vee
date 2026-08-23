## 1. Extract the shared menu model (no behavior change)

Design D1. This group must land green with **zero** user-visible change; the
existing `VeeMenuTests` / `VeeSearchTests` suites are the safety net.

- [ ] 1.1 Add `MenuRowSpec` to `VeeMenu`: the resolved description of one row —
      text attributes, icon, tooltip, checked/disabled state, accessory kind,
      actionability, key equivalent, and whether it is an alternate. Pure and
      AppKit-emitting-free enough to unit-test without building an `NSMenu`.
- [ ] 1.2 Add `MenuTree` to `VeeMenu`: resolves `[MenuNode]` into
      `[MenuRowSpec]` + children, owning node-to-row selection (`dropdown=false`,
      empty text, `header=true` section scope) and alternate placement.
- [ ] 1.3 Move actionability into the model as the single definition. Delete
      `MenuBuilder.isActionable` and `MenuFlattener.isActionable`; both call
      sites read `MenuRowSpec`. Include the submenu-wins-over-action rule.
- [ ] 1.4 Move accessory selection into the model. Delete the `if/else-if` chain
      in `MenuBuilder.makeItem` and `MenuRowAccessory.kind(for:)`; both read
      `MenuRowSpec.accessory`.
- [ ] 1.5 Rewrite `MenuBuilder` as a dumb `NSMenu` emitter over `MenuTree`.
      **Acceptance: no `params` inspection remains in `MenuBuilder`** — grep for
      `item.params` / `params.` in the file returns nothing.
- [ ] 1.6 Add `VeeMenuTests` covering the model directly: actionability across
      every param combination, accessory precedence, submenu-wins-over-action,
      `dropdown=false` exclusion, alternate placement, header section scope.
- [ ] 1.7 Verify `swift test` is green and the menu bar is unchanged by hand
      (nested submenus, alternates, `key=`, rich rows, headers, separators).

## 2. Remove cross-plugin search

Design D5. Independently revertible; do before the tree work so step 3 has less
surface to carry.

- [ ] 2.1 Delete `AppController.openSearchAllPanel`, `aggregateSearchRows`,
      `registerSearchAllHotkey`, `applySearchAllHotkey`, `searchHotkeyID`, and
      `searchHotkeyStatus`.
- [ ] 2.2 Delete the "Search All Plugins…" item, its `⌘F` binding, and the
      `onSearchAll` parameter from `MainMenuController` and its `AppController`
      call site.
- [ ] 2.3 Delete `searchAllHotkeyEnabled` / `searchAllHotkeyCombo` from
      `AppPreferences`. Leave the two `UserDefaults` keys orphaned — no
      migration (D5).
- [ ] 2.4 Delete the search-all hotkey row and its four model properties from
      `VeeUI/GeneralSettingsView`.
- [ ] 2.5 Delete `FlatRow.prefixed(with:)` and `SearchEntry.prefixed(with:)`.
- [ ] 2.6 Delete the `aggregateSearchRows` test suite and any
      `prefixed(with:)` coverage.
- [ ] 2.7 Make `MenuSearchPanel.present`'s `keepOpen:` non-optional and drop the
      `pluginName: "All Plugins"` special case — the aggregator was the only
      caller passing `nil`.
- [ ] 2.8 Verify `swift test` is green and no reference to search-all remains
      (`grep -ri "searchall\|search all"` over `Sources` and `Tests`).

## 3. Hierarchical tree view for the window and panel

Design D2, D3, D6. Specs: `detached-plugin-windows` — "Window content fidelity",
"The window keeps the panel's search".

- [ ] 3.1 Add tree filtering to `VeeSearch`: given a query, prune `MenuTree` to
      matching rows plus their ancestor chain, keeping authored order. Reuse
      `FuzzyScorer` / `SearchText` for matching; do **not** rank. Pure and
      unit-tested.
- [ ] 3.2 Add `MenuTreeView` (SwiftUI) in `VeeApp`: renders `MenuTree` with
      inline disclosure, replacing `MenuSearchContentView`'s flat list. Reuse
      the existing row rendering (`AttributedTitleFactory` bridge,
      `SearchRowIcon`, `MenuRowAccessory`); drop the breadcrumb line.
- [ ] 3.3 Carry over the existing keyboard model: ↑/↓ move selection across
      visible rows, Return activates, Esc dismisses (panel only). Add ←/→ to
      close/open the selected branch.
- [ ] 3.4 Replace `[SearchEntry]` with the tree in `MenuSearchViewModel` and
      `DetachedPluginWindowModel`. Keep the panel's frozen-at-open rule and the
      window's live `update(entries:)` path.
- [ ] 3.5 Point `DetachedPluginWindows` and `MenuSearchPanel` at `MenuTreeView`.
      Chrome stays with the presentation — the panel keeps its fixed Liquid
      Glass card and keep-open button, the window keeps its title-bar pin.
- [ ] 3.6 Delete `SearchEntry`, `MenuFlattener.flattenEntries`, and the
      normalization pass (`normalized`, `collapseSeparators`,
      `dropDanglingHeaders`) with its tests. D6 — a tree creates no dangling
      furniture to repair.
- [ ] 3.7 Confirm `MenuFlattener.flatten` / `FlatRow` / `FuzzyScorer` still
      build and `vee search` still works — it is now the only flat consumer.
- [ ] 3.8 Add tests: filter prunes to matches plus ancestors, ancestors
      auto-reveal, authored order preserved under filtering, ancestor-title
      match surfaces children, empty query shows full structure.

## 4. Expansion state across live refreshes

Design D4. Spec: "Open branches survive a refresh". The highest-risk group.

- [ ] 4.1 Key expansion by ancestor title path in `DetachedPluginWindowModel`,
      applied when a refresh replaces the tree.
- [ ] 4.2 Ensure a branch that cannot be matched after a refresh closes **alone**
      and never cascades into unrelated branches.
- [ ] 4.3 Confirm the byte-identical short-circuit in
      `StatusItemController.render` still skips re-deriving the tree, so a
      1-second plugin does not churn expansion state.
- [ ] 4.4 Add tests: a refresh with new values keeps a branch open; a vanished
      branch closes without affecting siblings; repeated refreshes leave open
      branches open.
- [ ] 4.5 Verify by hand against a fast plugin (≤5s interval) with two branches
      open, including one whose title changes each tick — confirm the
      degradation is confined to that branch.

## 5. Window controls

Design D7. Spec: "A window carries its plugin's controls".

- [ ] 5.1 Surface Refresh / Settings / About / Reveal in Finder / Edit Plugin /
      Debug in the detached window's chrome, routed through the same closures
      `ControlsTarget` already holds — no second action path.
- [ ] 5.2 Keep controls out of the row list so the filter cannot match them.
- [ ] 5.3 Bind `⌘R` and `⌘,` as window-level shortcuts; make `⌘F` focus the
      filter field in the window and panel. The menu bar's `⌘F` still opens the
      panel (an `NSMenu` cannot host a text field).
- [ ] 5.4 Add tests: controls are absent from filtered results for a query
      matching a control's name; refresh from a window re-runs the plugin.

## 6. Documentation

- [ ] 6.1 Update `ARCHITECTURE.md`: rewrite "The menu surface has two
      presentations" for the model-plus-two-emitters shape, and correct the
      renderer count in the "four things in total" paragraph.
- [ ] 6.2 Update the `VeeSearch` and `VeeMenu` rows in `ARCHITECTURE.md`'s module
      table to match their new responsibilities.
- [ ] 6.3 Withdraw the "search everything" slice from
      `docs/_content/roadmap.md`.
- [ ] 6.4 Remove Search All Plugins from `docs-site` (and any `⌘F` reference).
- [ ] 6.5 Add a `CHANGELOG.md` entry covering the removal — call out that an
      enabled global hotkey silently stops working and its combination frees up.

## 7. Verification

- [ ] 7.1 `swift test` green; `swiftlint` clean.
- [ ] 7.2 Menu bar regression pass by hand: nested submenus, `⌥` alternates,
      `key=` equivalents, section headers, separators, checked state, tooltips,
      and every rich row (progress, sparkline, pie/donut/stackedbar, toggle,
      slider).
- [ ] 7.3 Window/panel pass against the same plugin: same rows, same order, same
      actions, nesting openable in place, two branches open together.
- [ ] 7.4 Confirm activation parity — a row activated from the window does
      exactly what the same row does from the dropdown, including control
      commits and post-commit refresh.
- [ ] 7.5 Run the memory soak job to confirm the new view and expansion state
      introduce no growth over a sustained window.
- [ ] 7.6 `openspec validate unify-plugin-menu-surfaces --strict` still passes.
