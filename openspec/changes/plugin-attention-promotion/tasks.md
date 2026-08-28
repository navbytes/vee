# Tasks: plugin-attention-promotion

Depends on `plugin-bar-placement`; do not start until that change's
`BarPlacement` and `reconcilePlacement()` exist. Gate on
`swift build && swift test && swiftlint lint --strict`.

## 1. The escalation rule

- [ ] 1.1 Add `effectivePlacement(resting:needsAttention:)` (design.md §1) as a
  pure function next to `BarPlacement`, with no AppKit dependency.
  - `hidden` + attention → folded; `folded` + attention → own; `own` +
    attention → own; every placement without attention → itself
  - Applying it twice is the same as applying it once (one rung, never two)

## 2. Attention state and its clock

- [ ] 2.1 `StatusItemController`: a `needsAttention` flag driven from the two
  existing edges — `renderError` arms a promote timer, `render(_:)` arms a
  demote timer, each cancelling the other's pending work; `remove()` cancels
  both.
  - Injectable `promotionDelay` (default 60s) so tests run at 0.05s
  - A failure shorter than the delay never promotes
  - A recovery shorter than the delay never demotes
  - A plugin flapping faster than the delay stays promoted
  - No timer survives `remove()`
- [ ] 2.2 Feed `effectivePlacement(...)` into `reconcilePlacement()` instead of
  the stored placement, and reconcile on every attention change.
  - Promotion and demotion reuse the existing switch path: the last render (or
    the error surface) is repainted on the new surface, nothing is leaked
  - A promoted plugin returning to its own item reuses its `autosaveName` slot
- [ ] 2.3 Resting placement is never written by promotion.
  - After a promote/demote cycle, the stored placement is byte-identical
  - Changing resting placement while promoted recomputes from the new value
    (e.g. hidden→own while failing lands on `own`, not a second rung)

## 3. Opt-out

- [ ] 3.1 `AppPreferences.promotionDisabledIDs` / `isPromotionDisabled(_:)` /
  `setPromotionDisabled(_:id:)`, following `hotkeyDisabledIDs` exactly; cleared
  by `clearAllState(id:)` and included in `reconcileDiskState`'s candidate set.
- [ ] 3.2 Honour it in the attention path: a plugin with promotion disabled
  never escalates, and disabling it while promoted de-escalates immediately.
- [ ] 3.3 Surface it in two places: a Plugin Manager control, and a row in the
  promoted plugin's own menu beside "Restart Plugin".
  - The menu row appears only while the plugin is promoted
  - Choosing it returns the plugin to its resting placement without changing
    what is stored for that placement

## 4. Interaction with the home item

- [ ] 4.1 A plugin promoted from `hidden` becomes a folded row and participates
  in the home item's error roll-up like any other folded row; de-escalation
  clears its membership.
  - The warning glyph is never left stuck on after de-escalation, removal, or
    the plugin being disabled mid-failure
- [ ] 4.2 Confirm a disabled plugin and a `<vee.surface>widget` plugin never
  promote (no run, no controller).

## 5. Docs

- [ ] 5.1 Docs site: what promotion does, the one rung it moves, the 60s
  damping, and how to turn it off per plugin.
- [ ] 5.2 `docs/design/roadmap.md`: record promotion as shipped, and keep the
  deferred author-declared `alert=` item visible as the follow-up with its
  parity cost stated.

## 6. Verify

- [ ] 6.1 `swift build && swift test && swiftlint lint --strict`.
- [ ] 6.2 Manual QA at the GUI: a folded plugin broken on purpose (promotes to
  its own item, error menu explains it, recovery demotes); a hidden plugin
  broken on purpose (appears as a badged row); a plugin flapping every ~20s
  (promotes once, does not oscillate); opt-out from the promoted item;
  the promoted item returning to the same slot across repeated cycles.
