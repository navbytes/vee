# Proposal: detached-window-position-memory

## Why

A detached plugin window forgets everything about where the user put it: every
`show()` centers and cascades ("session-scoped by design" — a design decision
the client is now overruling), so reopening a closed window loses its place,
and nothing survives a relaunch — including the pin preference, which today
lives only in session memory. A window that exists to be left open and watched
is precisely the window whose place matters.

Display-reconnect restoration was suspected too, but the experiment cleared
it: with an extended display (Apple TV) disconnected and reconnected, macOS
returned the window in **both** pin states. No reconnect handler is built on a
repro we cannot produce; if the original physical-monitor failure resurfaces,
that becomes its own change.

## What Changes

- Each plugin's window remembers its frame — position and size — per plugin:
  reopening in the same session restores it, and so does reopening after a
  relaunch, via the platform's window frame autosave.
- Center-and-cascade placement still applies, but only to a window with no
  remembered frame (its first-ever open).
- A remembered frame whose screen is gone opens fully on a present screen
  (platform clamping).
- The pin preference (floating vs ordinary) persists across relaunches instead
  of dying with the session.
- Windows still never auto-reopen at launch — the existing relaunch behavior is
  untouched; only the *frame* of a window the user reopens is remembered.
- Explicit non-goal: no display-reconnect handling (see Why).

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

- `detached-plugin-windows`: "Opening a plugin in a window" gains frame-memory
  behavior (restore on reopen and across relaunch; first-open placement;
  absent-screen clamping), and "Window level is the user's choice" upgrades the
  floating-state memory from session-scoped to persistent.

## Impact

- `Sources/VeeApp/DetachedPluginWindows.swift` — frame autosave wiring,
  restore-before-cascade ordering, pin preference read/write through
  preferences instead of a session dictionary.
- `Sources/VeePreferences` — persisted per-plugin pin preference, following the
  existing preferences pattern.
- Tests: pin persistence round-trip through the preferences seam; the
  windowless test path (`attachesWindows: false`) keeps asserting bookkeeping
  unchanged. Frame autosave itself is platform behavior, exercised by manual
  QA.
- `docs/_content/plugin-authoring.md` — the window section notes that position
  is remembered.
