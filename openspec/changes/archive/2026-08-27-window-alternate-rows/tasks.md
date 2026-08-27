# Tasks: window-alternate-rows

## 1. Shared projection

- [x] 1.1 Add `alternatesActive` to `MenuTreeDisplay.visibleNodes`: idle with
  flag off drops `isAlternate` rows; idle with flag on swaps the alternate in
  for the primary immediately before it; `revealAll` (filtering) emits both and
  ignores the flag — with unit tests for all three modes and for a lone
  alternate with no primary neighbor
- [x] 1.2 Unit test: visible-list length and indices are identical across a
  flag toggle, so index-based selection is stable by construction

## 2. View model and modifier observer

- [x] 2.1 Add `optionHeld` to `MenuSearchViewModel`, feeding
  `MenuTreeDisplay`; recompute without resetting selection; unit tests for
  swap-under-selection and for filtering leaving results unchanged as the flag
  toggles
- [x] 2.2 Add the shared ⌥ observer: local `flagsChanged` monitor plus an
  initial `NSEvent.modifierFlags` snapshot on attach; lifecycle follows the
  surface (panel present/dismiss, window model create/close), mirroring the
  panel's existing key-monitor teardown

## 3. Wire and verify

- [x] 3.1 Attach the observer in `MenuSearchPanel` and
  `DetachedPluginWindows`; confirm `MenuSearchContentView` needs no changes and
  the AppKit dropdown path is untouched
- [x] 3.2 Manual QA with a plugin declaring alternates: dropdown swap
  unchanged; panel and window show one row, swap while ⌥ held, both findable
  under a query; selection stays put through the swap
- [x] 3.3 Docs site: note that alternates now swap in the panel and window,
  and that filtering surfaces both halves
