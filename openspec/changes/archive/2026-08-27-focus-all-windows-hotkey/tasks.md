# Tasks: focus-all-windows-hotkey

## 1. The action

- [x] 1.1 `DetachedPluginWindows.focusAll()`: activate, order every window
  front, make the first (name-sorted) key; no-op on the windowless seam — with
  a bookkeeping unit test alongside the existing seam tests
- [x] 1.2 "Bring All to Front" row at the top of the `DetachedWindowsMenu`
  submenu (separator below), routing to `focusAll()`; hidden with the row when
  nothing is open

## 2. Binding and configuration

- [x] 2.1 `AppPreferences.focusWindowsHotkey` (nullable string, nil = unbound)
  following the existing hotkey-binding pattern — with a round-trip unit test
- [x] 2.2 `AppController`: register on launch when bound, unregister and
  re-register on change, `nil` from `GlobalHotKeys.register` surfaced as the
  claimed-combo `HotkeyStatus`
- [x] 2.3 General settings row mirroring the plugin-settings hotkey
  presentation: combo field, status text, immediate apply

## 3. Verify and document

- [x] 3.1 Manual QA: bind a combo; bury an unpinned window under another app;
  press → every window fronts, one is key; press with none open → nothing;
  enter a claimed combo → status reports it; clear the binding → hotkey gone
  without relaunch
- [x] 3.2 Docs: preferences page gains the setting; the window section of
  `plugin-authoring.md` mentions the bring-all gesture and menu row
