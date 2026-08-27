# Proposal: item-surface-visibility

## Why

Plugins cannot target rows at individual surfaces: the only knob is
`dropdown=false`, which is all-or-nothing — and its semantics have already
forked (`MenuTree` drops the whole subtree; `MenuFlattener` keeps children
searchable in `vee search`). The motivating request: keep specific rows out of
search's fuzzy reach (e.g. a destructive action should not be one match +
Return away), and let authors subtract rows from surfaces where they make no
sense. Two distinct axes are involved — *where a row exists* and *whether a
query can surface it* — and conflating them produces the wrong feature.

## What Changes

- New item param `visibleOn=` (comma list): which surfaces the row exists on.
  Values: `menu` (dropdown), `search` (transient panel), `window` (detached
  window), `cli` (`vee search` / terminal view). Absent = all. **`widget` is
  deliberately not a value** — body items never reach the widget; that surface
  is targeted at plugin level via `<vee.surface>`.
- New item param `searchable=false`: the row is never surfaced by a filter
  query — in the panel, the window's filter box, or `vee search` — but remains
  visible and browsable when its surface's tree is idle.
- One inheritance rule for both params: effective flags = own ∩ ancestors'
  (a child can narrow, never resurrect). An `alternate=true` row inherits from
  its primary the same way — a hidden primary hides the pair.
- Hiding repairs structure per surface: consecutive/leading/trailing separators
  are coalesced and a header whose entire section is hidden is dropped, so
  subtraction does not leave visible holes.
- `dropdown=false` becomes a compatibility alias; declaring both it and
  `visibleOn=` emits a `Diagnostics` warning and `visibleOn` wins. Unknown
  `visibleOn` values emit a diagnostic and are ignored.
- `MenuFlattener` (`vee search`) is aligned to the same subtree semantics,
  ending the existing `dropdown=false` fork.
- Full authoring surface: line params, JSON output, TypeScript/Python/Go SDKs,
  JSON schema, fixtures, docs site.

## Capabilities

### New Capabilities

- `item-surface-visibility`: per-item surface targeting and searchability —
  param semantics, inheritance, alternate interplay, structure repair,
  compatibility with `dropdown=`, and authoring-surface coverage.

### Modified Capabilities

- `menu-surface-model`: the "presentations agree on which rows exist" invariant
  gains its one licensed exception — a row a plugin *explicitly* targets away
  from a surface. Agreement remains the rule for everything undeclared.

## Impact

- `Sources/VeePluginFormat` — `LineParams`, `LineParameterKeys`,
  `JSONOutputParser`, `MenuTree.build(surface:)` (the single filter point),
  `Diagnostics`.
- `Sources/VeeSearch` — `MenuFlattener` alignment, `MenuTreeFilter`/`MenuSearch`
  respect `searchable`.
- `Sources/VeeApp` — dropdown, panel, and window each request their surface's
  tree (`StatusItemController.render`, `MenuSearchPanel.present`,
  `DetachedPluginWindows.show/update`).
- `plugins/typescript|python|go` SDKs + shared fixtures + drift tests,
  `docs/schemas`, docs site.
- Depends on nothing; `window-alternate-rows` composes with it (its
  idle-swap/filter-default is the no-flag behavior).
