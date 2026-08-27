# Tasks: item-surface-visibility

## 1. Format layer

- [x] 1.1 Parse `visibleOn=` (comma list) and `searchable=` into `LineParams`;
  register in `LineParameterKeys`; diagnostics for unknown surface values and
  for the all-values-unknown fallback — with parser unit tests
- [x] 1.2 Accept the same keys in `JSONOutputParser` with identical semantics —
  tests

## 2. Resolution

- [x] 2.1 Add `MenuSurface` (`menu`/`search`/`window`/`cli`) and thread it
  through `MenuTree.build(_:surface:)`: membership filter with ancestor
  intersection, subtree hiding, alternate = primary ∩ own; expose decided
  `isSearchable` on `MenuRowSpec` — unit tests per rule
- [x] 2.2 Structure repair after hiding: coalesce separator runs, drop emptied
  header sections; runs only when hiding removed a node — tests including
  byte-identical trees for declaration-free menus
- [x] 2.3 Compile `dropdown=false` onto the same mechanism; conflict with
  `visibleOn` resolves to `visibleOn` plus a diagnostic — tests
- [x] 2.4 Align `MenuFlattener` (`vee search`): subtree semantics for hidden
  rows, skip unsearchable rows — update its tests for the ended fork
- [x] 2.5 Honor `isSearchable` in `MenuTreeFilter.matches` and `MenuSearch`
  scoring; an unsearchable row still rides along inside a matching ancestor's
  kept subtree — tests

## 3. Surface plumbing

- [x] 3.1 Pass the right surface from each caller:
  `StatusItemController.render` (menu), `MenuSearchPanel.present` (search),
  `DetachedPluginWindows.show`/`update` (window), CLI entry points (cli)

## 4. Authoring surface

- [x] 4.1 TypeScript SDK: `visibleOn`/`searchable` options, emission order,
  plus a fixture example exercising both axes end-to-end
- [x] 4.2 Python SDK: same options and emission
- [x] 4.3 Go SDK: same options and emission
- [x] 4.4 JSON schema and docs-site parameter reference updated, including the
  `dropdown=` alias note and the deliberate absence of a `widget` value

## 5. Verify

- [ ] 5.1 End-to-end: fixture flows SDK → golden file → Swift parser tests;
  diagnostics visible in the plugin debug surface; manual QA of a plugin using
  `visibleOn` and `searchable=false` across dropdown, panel, window, and
  `vee search`
  - Done: `surfaces.txt` flows from all three SDKs → golden → drift guards →
    `FixtureRoundTripTests.testSurfacesFixtureParams`; `json-demo.txt` carries
    the JSON spelling; diagnostics confirmed on the shared `ParsedOutput`
    .diagnostics path the debug console reads (`vee lint` reports the unknown
    value, the all-unknown fallback, and the `dropdown=`/`visibleOn=` conflict);
    `vee search` verified against the fixture (targeted-away row absent,
    `searchable=false` row unmatched, subtree kept with its parent)
  - Remaining, needs a human at the GUI: the same plugin checked by eye in the
    dropdown, the search panel, and a detached window
