# Proposal: focus-all-windows-hotkey

## Why

An unpinned detached window buried under other apps has exactly one route back:
the menu-bar submenu, mouse-only and one window at a time. Vee is an accessory
app — no Dock icon, no App Exposé — so a user running several windows as a
dashboard has no single gesture that says "bring my windows back." A global
hotkey is that gesture; plugins already get per-plugin hotkeys, but the
app-level "all of them" action does not exist.

## What Changes

- An app-level global hotkey that brings every open detached window to the
  front and activates Vee, with one window made key deterministically. With no
  windows open it does nothing — the existing philosophy that a retrieval
  hotkey never opens windows behind the user's back.
- Unbound by default (global combos are contested space). Configured in
  Preferences → General with the same combo format, immediate apply, and
  validity/collision reporting (`HotkeyStatus`) plugin hotkeys already have.
- A "Bring All to Front" row in the Detached Windows submenu — the same action,
  discoverable and mouse-reachable, matching the macOS Window-menu idiom.
- The transient panel is untouched: it cannot be buried (it dismisses on
  outside click), so it has nothing to retrieve.

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

- `detached-plugin-windows`: the "Open windows are listed and retrievable"
  requirement grows the one-gesture retrieval path — the menu action and the
  optional global hotkey, with its configuration and no-windows behavior.

## Impact

- `Sources/VeeApp/DetachedPluginWindows.swift` — `focusAll()`.
- `Sources/VeeApp/DetachedWindowsMenu.swift` — the "Bring All to Front" row.
- `Sources/VeePreferences/AppPreferences.swift` — binding storage (one string
  key, following the existing hotkey-binding pattern).
- `Sources/VeeApp/AppController.swift` — registration lifecycle via the
  existing Carbon `GlobalHotKeys` (no new hotkey machinery).
- `Sources/VeeUI/GeneralSettingsView.swift` — the combo field + status row,
  mirroring the plugin-settings hotkey presentation.
- Docs: preferences page and the window section of plugin-authoring.
