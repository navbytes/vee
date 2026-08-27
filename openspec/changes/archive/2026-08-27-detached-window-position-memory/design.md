# Design: detached-window-position-memory

## Context

See proposal.md — Why. `DetachedPluginWindows.show()` today does
`window.center()` + `cascadeTopLeft` on every open, with an explicit "no frame
autosave" comment; `pinPreference` is a session dictionary. App-level
preferences live in `VeePreferences` (UserDefaults-backed). The manager has a
windowless test seam (`attachesWindows: false`) that asserts bookkeeping
without AppKit effects.

## Goals / Non-Goals

**Goals:**
- Frame memory per plugin — reopen and relaunch — with the least code that can
  do it, leaning on the platform.
- Pin preference that survives a relaunch, through the existing preferences
  layer.

**Non-Goals:**
- No display-reconnect handling: the Apple TV experiment showed macOS restores
  the window to a reattached display in both pin states. If the original
  physical-monitor failure ever reproduces, the sketch on record is a
  `didChangeScreenParametersNotification` observer restoring frames keyed by a
  display-set fingerprint — its own change, evidence first.
- No window restoration at launch ("Windows do not survive a relaunch" stands).
- No frame memory for the transient panel (mouse-anchored by design).

## Decisions

1. **AppKit frame autosave, not hand-rolled persistence.** Per-plugin name
   (`"DetachedPluginWindow <plugin>"`); order matters and is the whole
   implementation: after creating the window, `setFrameUsingName` — if it
   returns false (first-ever open), `center()` + cascade as today — then
   `setFrameAutosaveName`, so moves and resizes save continuously from that
   point. Setting the autosave name *after* placement keeps the initial
   center/cascade from overwriting a saved frame. This buys relaunch
   persistence and offscreen clamping (the "screen is gone" scenario) for
   free. Alternative — tracking `didMove`/`didResize` into our own store —
   rejected: reimplements the platform.

2. **Pin preference moves into `VeePreferences`,** replacing the session
   dictionary as the source of truth (the dictionary survives only as whatever
   caching the preferences type itself does). Follows the existing
   `AppPreferences` pattern and its test seam, so the round-trip
   (set → relaunch-shaped reload → read) is unit-testable. The default stays
   pinned.

3. **The windowless seam keeps its meaning.** Frame autosave is an effect on a
   real `NSWindow` and happens only on the `attachesWindows` path, like the
   window itself; bookkeeping assertions are unaffected. Frame behavior is
   verified by manual QA, pin persistence by unit test — the same
   testable-vs-effect split the manager already documents.

## Risks / Trade-offs

- [Frame autosave writes into the app's defaults domain; the dev build
  (`swift run vee`) and the installed app have different domains] → Expected
  and harmless: each keeps its own memory. QA within one build.
- [A plugin renamed on disk orphans its saved frame and pin preference] →
  Accepted; one stale defaults entry per rename, the window simply gets
  first-open placement again.
- [Autosave clamping on a vanished screen is platform behavior, not ours] →
  That is the point of decision 1; the scenario is QA-verified, not
  unit-tested.

## Open Questions

None.
