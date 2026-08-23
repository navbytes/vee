## 1. Extract the shared menu model (no behavior change)

Design D1. This group must land green with **zero** user-visible change; the
existing `VeeMenuTests` / `VeeSearchTests` suites are the safety net.

- [x] 1.1 Add `MenuRowSpec` to **`VeePluginFormat`** (not `VeeMenu`: `VeeUI` and
      `VeeMenu` are siblings and cannot see each other, so the shared model must
      sit in the module both depend on). Carries decisions only — actionability,
      enabled/checked/header state, display-graphic selection, control presence,
      accessory placement, key equivalent, alternate — keeping the module
      Foundation-only. AppKit resolution stays in `AttributedTitleFactory` /
      `SymbolImageFactory`, which both emitters already share.
- [x] 1.2 Add `MenuTree` to `VeePluginFormat`: resolves `[MenuNode]` into
      `[MenuTreeNode]`, owning node-to-row selection (`dropdown=false`,
      empty text, `header=true` section scope) and alternate placement.
- [x] 1.3 Move actionability into the model as the single definition. Delete
      `MenuBuilder.isActionable` and `MenuFlattener.isActionable`; both call
      sites read `MenuRowSpec`. Include the submenu-wins-over-action rule.
- [x] 1.4 Move display-graphic selection (progress → sparkline → chart) into the
      model as one rule. Delete the `if/else-if` chain in `MenuBuilder.makeItem`
      and the graphic branches of `MenuRowAccessory.kind(for:)`; both read
      `MenuRowSpec.accessory`. Whether a live control is drawn inline stays with
      the presentation — the menu bar cannot host one (see the amended
      "A live control is presented per surface" scenario).
- [x] 1.5 Rewrite `MenuBuilder` as a dumb `NSMenu` emitter over `MenuTree`.
      **Acceptance: no decision logic on `params` remains in `MenuBuilder`** — no
      `if`/`??`/comparison branching on a param. Delegating calls that hand
      `params` wholesale to the shared `AttributedTitleFactory` /
      `SymbolImageFactory` are not decisions and are expected to remain.
- [x] 1.6 Add `VeeMenuTests` covering the model directly: actionability across
      every param combination, accessory precedence, submenu-wins-over-action,
      `dropdown=false` exclusion, alternate placement, header section scope.
- [ ] 1.7 Verify `swift test` is green and the menu bar is unchanged by hand
      (nested submenus, alternates, `key=`, rich rows, headers, separators).
      **Automated half done** — 1058 tests green, swiftlint clean. The by-hand
      menu-bar pass needs a real session and is left for the user; it can be
      folded into the 7.2 regression pass.

## 2. Remove cross-plugin search

Design D5. Independently revertible; do before the tree work so step 3 has less
surface to carry.

- [x] 2.1 Delete `AppController.openSearchAllPanel`, `aggregateSearchRows`,
      `registerSearchAllHotkey`, `applySearchAllHotkey`, `searchHotkeyID`, and
      `searchHotkeyStatus`.
- [x] 2.2 Delete the "Search All Plugins…" item, its `⌘F` binding, and the
      `onSearchAll` parameter from `MainMenuController` and its `AppController`
      call site.
- [x] 2.3 Delete `searchAllHotkeyEnabled` / `searchAllHotkeyCombo` from
      `AppPreferences`. Leave the two `UserDefaults` keys orphaned — no
      migration (D5).
- [x] 2.4 Delete the search-all hotkey row and its four model properties from
      `VeeUI/GeneralSettingsView`.
- [x] 2.5 Delete `FlatRow.prefixed(with:)` and `SearchEntry.prefixed(with:)`.
- [x] 2.6 Delete the `aggregateSearchRows` test suite and any
      `prefixed(with:)` coverage.
- [x] 2.7 Make `MenuSearchPanel.present`'s `keepOpen:` non-optional and drop the
      `pluginName: "All Plugins"` special case — the aggregator was the only
      caller passing `nil`.
- [x] 2.8 Verify `swift test` is green and no reference to search-all remains
      (`grep -ri "searchall\|search all"` over `Sources` and `Tests`).

## 3. Hierarchical tree view for the window and panel

Design D2, D3, D6. Specs: `detached-plugin-windows` — "Window content fidelity",
"The window keeps the panel's search".

- [x] 3.1 Add tree filtering to `VeeSearch`: given a query, prune `MenuTree` to
      matching rows plus their ancestor chain, keeping authored order. Reuse
      `FuzzyScorer` / `SearchText` for matching; do **not** rank. Pure and
      unit-tested.
- [x] 3.2 Add `MenuTreeView` (SwiftUI) in `VeeApp`: renders `MenuTree` with
      inline disclosure, replacing `MenuSearchContentView`'s flat list. Reuse
      the existing row rendering (`AttributedTitleFactory` bridge,
      `SearchRowIcon`, `MenuRowAccessory`); drop the breadcrumb line.
- [x] 3.3 Carry over the existing keyboard model: ↑/↓ move selection across
      visible rows, Return activates, Esc dismisses (panel only). Add ←/→ to
      close/open the selected branch.
- [x] 3.4 Replace `[SearchEntry]` with the tree in `MenuSearchViewModel` and
      `DetachedPluginWindowModel`. Keep the panel's frozen-at-open rule and the
      window's live `update(entries:)` path.
- [x] 3.5 Point `DetachedPluginWindows` and `MenuSearchPanel` at `MenuTreeView`.
      Chrome stays with the presentation — the panel keeps its fixed Liquid
      Glass card and keep-open button, the window keeps its title-bar pin.
- [x] 3.6 Delete `SearchEntry`, `MenuFlattener.flattenEntries`, and the
      normalization pass (`normalized`, `collapseSeparators`,
      `dropDanglingHeaders`) with its tests. D6 — a tree creates no dangling
      furniture to repair.
- [x] 3.7 Confirm `MenuFlattener.flatten` / `FlatRow` / `FuzzyScorer` still
      build and `vee search` still works — it is now the only flat consumer.
- [x] 3.8 Add tests: filter prunes to matches plus ancestors, ancestors
      auto-reveal, authored order preserved under filtering, ancestor-title
      match surfaces children, empty query shows full structure.

## 4. Expansion state across live refreshes

Design D4. Spec: "Open branches survive a refresh". The highest-risk group.

- [x] 4.1 Key expansion by ancestor title path in `DetachedPluginWindowModel`,
      applied when a refresh replaces the tree.
- [x] 4.2 Ensure a branch that cannot be matched after a refresh closes **alone**
      and never cascades into unrelated branches.
- [x] 4.3 Confirm the byte-identical short-circuit in
      `StatusItemController.render` still skips re-deriving the tree, so a
      1-second plugin does not churn expansion state.
- [x] 4.4 Add tests: a refresh with new values keeps a branch open; a vanished
      branch closes without affecting siblings; repeated refreshes leave open
      branches open.
- [ ] 4.5 Verify by hand against a fast plugin (≤5s interval) with two branches
      open, including one whose title changes each tick — confirm the
      degradation is confined to that branch.
      **Needs a real session — left for the user.** Everything automatable is green: 1062 tests, swiftlint --strict clean, the app builds and launches without crashing, and the soak reports 450/450 refreshes with 0.2MB growth.

## 5. Window controls

Design D7. Spec: "A window carries its plugin's controls".

- [x] 5.1 Surface Refresh / Settings / About / Reveal in Finder / Edit Plugin /
      Debug in the detached window's chrome, routed through the same closures
      `ControlsTarget` already holds — no second action path.
- [x] 5.2 Keep controls out of the row list so the filter cannot match them.
- [x] 5.3 Bind `⌘R` and `⌘,` as window-level shortcuts; make `⌘F` focus the
      filter field in the window and panel. The menu bar's `⌘F` still opens the
      panel (an `NSMenu` cannot host a text field).
- [x] 5.4 Add tests: controls are absent from filtered results for a query
      matching a control's name; refresh from a window re-runs the plugin.

## 6. Documentation

- [x] 6.1 Update `ARCHITECTURE.md`: rewrite "The menu surface has two
      presentations" for the model-plus-two-emitters shape, and correct the
      renderer count in the "four things in total" paragraph.
- [x] 6.2 Update the `VeeSearch` and `VeeMenu` rows in `ARCHITECTURE.md`'s module
      table to match their new responsibilities.
- [x] 6.3 Withdraw the "search everything" slice from
      `docs/_content/roadmap.md`.
- [x] 6.4 Remove Search All Plugins from `docs-site` (and any `⌘F` reference).
- [x] 6.5 Add a `CHANGELOG.md` entry covering the removal — call out that an
      enabled global hotkey silently stops working and its combination frees up.

## 7. Verification

- [x] 7.1 `swift test` green; `swiftlint` clean.
- [ ] 7.2 Menu bar regression pass by hand: nested submenus, `⌥` alternates,
      `key=` equivalents, section headers, separators, checked state, tooltips,
      and every rich row (progress, sparkline, pie/donut/stackedbar, toggle,
      slider).
      **Needs a real session — left for the user.** Everything automatable is green: 1062 tests, swiftlint --strict clean, the app builds and launches without crashing, and the soak reports 450/450 refreshes with 0.2MB growth.
- [ ] 7.3 Window/panel pass against the same plugin: same rows, same order, same
      actions, nesting openable in place, two branches open together.
      **Needs a real session — left for the user.** Everything automatable is green: 1062 tests, swiftlint --strict clean, the app builds and launches without crashing, and the soak reports 450/450 refreshes with 0.2MB growth.
- [ ] 7.4 Confirm activation parity — a row activated from the window does
      exactly what the same row does from the dropdown, including control
      commits and post-commit refresh.
      **Needs a real session — left for the user.** Everything automatable is green: 1062 tests, swiftlint --strict clean, the app builds and launches without crashing, and the soak reports 450/450 refreshes with 0.2MB growth.
- [x] 7.5 Run the memory soak job to confirm the new view and expansion state
      introduce no growth over a sustained window.
- [x] 7.6 `openspec validate unify-plugin-menu-surfaces --strict` still passes.
