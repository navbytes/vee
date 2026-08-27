# Design: focus-all-windows-hotkey

## Context

See proposal.md — Why. Everything needed exists: `GlobalHotKeys` (Carbon
`RegisterEventHotKey`, no Accessibility permission, returns `nil` on a claimed
combo), `HotKeySpec.parse` for combo strings, `HotkeyStatus` for
validity/collision reporting, `AppPreferences` string-keyed hotkey storage,
`DetachedWindowsMenu` (self-filling submenu, hidden when empty), and
`DetachedPluginWindows` with its windowless test seam.

## Goals / Non-Goals

**Goals:**
- One new action wired through existing machinery — no new hotkey
  infrastructure, no third-party recorder.
- Same configuration feel as plugin hotkeys: combo string, immediate apply,
  honest status.

**Non-Goals:**
- Retrieving the transient panel (cannot be buried; dismisses on outside
  click).
- Opening windows that are not open, or remembering/restoring window sets.
- MRU tracking to choose the key window — no such state exists and one
  deterministic choice serves the gesture.
- A toggle/hide-all second press.

## Decisions

1. **`DetachedPluginWindows.focusAll()`**: activate Vee, `orderFront` every
   window, `makeKeyAndOrderFront` the first in `openPlugins` order
   (name-sorted — the ordering the feature already uses for its menu). On the
   windowless seam it is a no-op, like `focus(pluginName:)`.
2. **Registration lives in `AppController`,** beside the plugin-hotkey
   lifecycle: register on launch when a binding exists, unregister/re-register
   on change, action dispatches to `focusAll()`. `register` returning `nil`
   maps to the claimed-combo `HotkeyStatus`, exactly as for plugins.
3. **Storage is one nullable string** in `AppPreferences`
   (`focusWindowsHotkey`), `nil` = unbound = nothing registered. Follows the
   existing `hotkeyBinding` pattern and its test seam.
4. **UI is a row in General settings** mirroring the plugin-settings hotkey
   presentation (combo field + status text, apply-on-edit). No recorder
   control is introduced; parity with plugin hotkeys is the feature.
5. **The menu row** goes at the top of the Detached Windows submenu with a
   separator below it, hidden with the row itself when nothing is open —
   so the no-windows scenario needs no separate guard in the menu path.

## Risks / Trade-offs

- [A combo the user expects fails silently if another app claims it later
  (Carbon steals-back semantics)] → Same exposure plugin hotkeys already have;
  status reports it at apply time, which is when the user is looking.
- [Multiple unpinned windows across several Spaces: macOS switches to the key
  window's Space; windows on other Spaces front within theirs] → Platform
  behavior, acceptable for the gesture; documented in QA notes rather than
  fought.

## Open Questions

None.
