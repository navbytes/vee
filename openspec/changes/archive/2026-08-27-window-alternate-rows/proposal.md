# Proposal: window-alternate-rows

## Why

A row with `alternate=true` swaps in for its primary while ⌥ is held in the
menu-bar dropdown (native AppKit behavior), but the two SwiftUI tree surfaces —
the transient search panel and the detached window — render **both rows at
once, always**: `MenuTree` resolves the pair correctly (`MenuRowSpec.isAlternate`),
and then no SwiftUI surface reads the flag. The shared model did its job; the
presentation layer never consumed it. The result looks like a duplicated row
and hides the ⌥ affordance plugins authored.

## What Changes

- `MenuTreeDisplay` (the shared, pure projection every tree surface draws)
  learns to resolve an alternate pair into **one visible row**, chosen by the
  current ⌥ state — the decision lives in the shared layer, not in either
  renderer.
- While a filter query is active, ⌥ is inert and **both** rows are ordinary
  match candidates — a query is explicit intent, and this matches what
  `MenuFlattener` already does for `vee search`.
- The panel and the detached window observe the ⌥ modifier (one shared
  `flagsChanged` observer) and feed it to the projection; swapping preserves
  the keyboard selection index (the swap is 1:1 in place).
- The AppKit dropdown and the CLI are untouched.

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

- `menu-surface-model`: the "alternate replaces its row under the modifier"
  scenarios are today satisfiable by *not* supporting alternates ("in a
  presentation that supports modifier-held alternates"). The requirement is
  strengthened: every tree presentation (panel, window) SHALL support
  modifier-held alternates, and the behavior of an alternate pair under an
  active filter query is defined (both matchable, modifier inert).

## Impact

- `Sources/VeeSearch/MenuTreeDisplay.swift` — alternate resolution in
  `visibleNodes` (new `alternatesActive` input).
- `Sources/VeeApp/MenuSearchViewModel.swift` — carries the ⌥ state, recomputes
  on change; selection stability across the swap.
- `Sources/VeeApp/MenuSearchContentView.swift` / `MenuSearchPanel.swift` /
  `DetachedPluginWindows.swift` — one shared ⌥ observer feeding the model.
- Unit tests in `VeeSearch`/`VeeApp` test targets (pure projection + view model;
  no real windows needed — the existing test seams cover this).
- Known accepted edge: an alternate with its own submenu changes the row's
  title-path key when swapped, so an open branch under the primary closes while
  ⌥ is held. Rare, cosmetic, documented.
