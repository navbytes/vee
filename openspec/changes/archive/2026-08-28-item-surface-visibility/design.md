# Design: item-surface-visibility

## Context

See proposal.md — Why. Every app surface renders the resolved tree
(`MenuTree.build` → `[MenuTreeNode]`); the CLI's flat search uses
`MenuFlattener`. `dropdown=false` is today read in both, with forked subtree
semantics. Params flow: `LineParser`/`JSONOutputParser` → `LineParams` →
`MenuTree`. Three SDKs (TS/Python/Go) emit the line format and are kept honest
by golden fixtures shared with the Swift parser tests.

## Goals / Non-Goals

**Goals:**
- One filter point per axis: surface membership decided in `MenuTree.build`,
  query reach decided in the shared matchers — no renderer ever consults the
  params.
- End the `dropdown=false` semantic fork while keeping every existing plugin's
  observable behavior.

**Non-Goals:**
- No `widget` value (body rows never reach the widget surface).
- No per-surface *content* (different text per surface); targeting only
  subtracts.
- No UI for authoring; this is a format feature.

## Decisions

1. **`MenuTree.build(_:surface:)` is the membership filter.** A `MenuSurface`
   enum (`menu`, `search`, `window`, `cli`) is threaded from each caller:
   `StatusItemController.render` (menu), `MenuSearchPanel.present` (search),
   `DetachedPluginWindows.show/update` (window), CLI (cli). A row whose
   effective `visibleOn` excludes the surface is skipped with its subtree —
   the exact path `dropdown=false` already takes there, now shared.
   Alternative — filtering in `MenuTreeDisplay` per render — rejected: display
   runs on every keystroke/⌥ change; membership is a parse-time fact.

2. **Effective flags are computed during the walk, not stored.** The build
   walk carries the ancestor intersection down (visibleOn: set intersection;
   searchable: AND). Alternates take `primary ∩ own`. No new fields on
   `MenuItem`; `MenuRowSpec` gains only `isSearchable` so matchers can read
   the decided value.

3. **`searchable` is enforced in the two matchers.** `MenuTreeFilter.matches`
   and `MenuSearch`'s scorer skip `isSearchable == false` rows; such a row can
   still be *kept* as the untouched subtree of a matching ancestor (the
   tree filter's "a hit keeps everything under it" rule is unchanged — the row
   just never earns a hit itself). This preserves the browsable-when-idle
   guarantee with zero renderer changes.

4. **Structure repair is a small shared pass.** After membership filtering,
   `MenuTree.build` coalesces separator runs and drops emptied
   header sections, once, for all surfaces. It runs only when hiding actually
   removed a node, so undeclared menus keep byte-identical trees (and the
   "structural elements are not invented" scenarios keep holding).

5. **`dropdown=false` maps onto the same mechanism.** It compiles to
   "hidden on menu/search/window/cli" (its `MenuTree` behavior today), which
   changes one thing deliberately: `vee search` stops surfacing its children —
   the spec'd fork-ending. Conflict with an explicit `visibleOn` resolves to
   `visibleOn` plus a `Diagnostics` entry, consistent with the parser's
   existing tolerant-with-diagnostics posture. Menu-bar *title* lines are not
   body rows; their `dropdown=false` handling is untouched.

6. **SDK shape: `visibleOn: Surface[]` + `searchable: boolean`,** emitted as
   `visibleOn=menu,window` / `searchable=false` line params and matching JSON
   keys; one new fixture example exercises both axes end-to-end (SDK → fixture
   → Swift parser test), extending the existing drift harness rather than
   inventing a parallel one.

## Risks / Trade-offs

- [Three trees per plugin (menu/search/window) instead of one shared build] →
  Build is cheap and already runs per refresh; window/panel builds happen on
  open/update only. If profiling ever disagrees, memoize by (output, surface).
- [Ending the `vee search` children-of-hidden-rows behavior is observable] →
  Deliberate and spec'd; called out in docs as the fork it fixes. No known
  plugin depends on it.
- [Vocabulary lock-in: surface names become API] → Names match the surfaces
  users see (menu/search/window/cli); unknown values are ignored-with-
  diagnostic, so the set can grow without breaking older Vee versions.

## Open Questions

None.
