# Design: window-alternate-rows

## Context

See proposal.md — Why. `MenuTree.build` already emits the alternate as a
sibling `MenuRowSpec` with `isAlternate: true` directly after its primary
(inheriting the primary's `key=`), and the AppKit dropdown gets the swap free
from `NSMenuItem.isAlternate`. The SwiftUI surfaces (panel + detached window)
share one view model (`MenuSearchViewModel`) and one content view, and render
`MenuTreeDisplay.visibleNodes(...)` — a pure projection with existing unit-test
coverage. Nothing SwiftUI-side reads `isAlternate` today.

## Goals / Non-Goals

**Goals:**
- The ⌥ swap decision lives in the shared pure layer, unit-tested without a
  window; renderers stay dumb.
- Panel and window get the swap from one implementation; the dropdown and CLI
  are untouched.

**Non-Goals:**
- No change to `MenuTree`'s pairing or key-inheritance rules.
- No attempt to swap within active filter results (spec: modifier inert while
  filtering).
- No handling for ⌥ held *before* the surface opens beyond reading the current
  modifier state at open.

## Decisions

1. **Resolution lives in `MenuTreeDisplay`.** `visibleNodes` gains an
   `alternatesActive: Bool` (default false). Idle: when false, drop
   `isAlternate` rows; when true, drop a primary immediately followed by its
   alternate. With `revealAll` (filtering), both are emitted regardless and the
   flag is ignored. Alternative — resolving in each SwiftUI view — rejected:
   that is exactly the per-renderer drift this change exists to end.
   `MenuFlattener`/CLI keep their peer-row behavior, which the spec now names.

2. **One ⌥ observer, owned by the view model.** `MenuSearchViewModel` gains
   `optionHeld`, set by an `NSEvent` local `flagsChanged` monitor plus the
   current `NSEvent.modifierFlags` snapshot on attach (so opening with ⌥
   already down starts swapped). A local monitor only fires while Vee is
   active — correct here, since both surfaces are key windows when in use.
   The monitor's lifecycle follows the surface (attach on present/open, remove
   on dismiss/close), mirroring how `MenuSearchPanel` already manages its
   key-down monitor.

3. **Selection is stable by construction.** The swap is a 1:1 in-place
   replacement, so the visible list's length and indices are unchanged and the
   existing index-based selection needs no correction. A unit test pins this.

4. **Alternate rows filter as ordinary rows.** `MenuTreeFilter` needs no
   change: alternates are already ordinary `MenuTreeNode`s in the tree, so
   matching them independently falls out. Only the idle projection changes.

## Risks / Trade-offs

- [An alternate declaring children changes its title-path key when swapped, so
  a branch opened under the primary closes under ⌥] → Accepted as cosmetic and
  rare; documented in the proposal. Revisit only if a real plugin hits it.
- [Local event monitors leak if removal is missed] → Follow the existing
  `MenuSearchPanel` monitor teardown pattern; the detached-window model removes
  its monitor in the same close path that already unregisters its
  close-observer token.
- [Panel loses key status while ⌥ held elsewhere, going stale] → On
  `flagsChanged` attach, also re-read modifier state on window
  key-status change; cheap and covered by the existing focus plumbing.

## Open Questions

None.
