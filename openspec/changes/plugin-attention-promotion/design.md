# Design: plugin-attention-promotion

## Context

See proposal.md — Why. Depends on `plugin-bar-placement`: this change adds a
second input to that change's `reconcilePlacement()` and reuses its
`BarPlacement`.

The two edges already exist and are the only ones needed.
`StatusItemController.render(_:)`
(`Sources/VeeApp/StatusItemController.swift:276`) clears `lastErrorMessage`;
`renderError(...)` (`:323`) sets it, and is called from every failure the
runtime classifies — timeout, non-zero exit with no usable output, and
spawn/stream errors (`PluginCoordinator.swift:549-574`). "Is this plugin
failing" therefore needs no new detection, only a clock.

**No spec deltas** — `skip_specs: true`, for the same reason as
`plugin-bar-placement`. This document and `tasks.md` are the authority.

## Goals / Non-Goals

**Goals:**
- A failing plugin becomes visible without the user having placed it well in
  advance.
- Resting placement is never silently rewritten.
- The bar never shuffles on a plugin that is merely noisy.

**Non-Goals:**
- Author-declared alerts for a healthy plugin (deferred; see proposal).
- Promotion for a plugin whose resting placement is already `own` — it is
  already maximally visible, and its glyph already swaps to the error symbol.
- Any notification, sound, or badge outside the menu bar. `Notifier` already
  owns alerting; this is about placement only.

## Decisions

### 1. Effective placement = escalate(resting, attention)

```swift
// one pure function, unit-testable with no AppKit
func effectivePlacement(resting: BarPlacement, needsAttention: Bool) -> BarPlacement {
    guard needsAttention else { return resting }
    switch resting {
    case .hidden:        return .foldedDefault  // becomes a badged row in the home item
    case .folded:        return .own            // becomes its own item
    case .own:           return .own            // already maximally visible
    }
}
```

`reconcilePlacement()` is fed `effectivePlacement(...)` instead of the stored
value; everything downstream — teardown, rebuild, repaint, position memory — is
unchanged. Resting placement is read from `AppPreferences` and never written by
this change.

One rung, not straight to `own`: a user who deliberately took a plugin out of
the menu bar should not get a new icon appearing there unannounced. A badge on
an icon that is already present is the proportionate escalation, and it is
still a decisive improvement over silence.

### 2. Attention is the controller's existing error state, plus a clock

No new classification. `needsAttention` flips on a timer, not on the edge
itself:

- `renderError` starts a 60s timer; on fire, `needsAttention = true` and
  reconcile.
- `render(_:)` (a successful render) starts a 60s timer; on fire,
  `needsAttention = false` and reconcile.
- Either edge cancels the other's pending timer first.

**One symmetric constant, both directions.** A plugin flapping faster than 60s
never accumulates 60s of health, so it stays promoted — correct, because a
plugin that oscillates *is* unhealthy. A plugin with a 1h interval promotes 60s
after its failed run rather than an hour later.

*Rejected:* "N consecutive failed runs". It reads well but scales with the
plugin's interval in the wrong direction — a 10s plugin promotes on a
transient blip, a 1h plugin stays invisible for hours. Time is the thing the
user actually cares about.

The interval is injectable (`promotionDelay`, defaulting to 60s) so tests run
at 0.05s rather than sleeping. The pending work is a `DispatchWorkItem`
cancelled on the opposite edge and on `remove()` — the same shape
`dimWorkItem` already uses (`:412`).

### 3. Opt-out is per plugin, stored as a departure

`promotionDisabledIDs` in `AppPreferences`, following `hotkeyDisabledIDs`
exactly: the map stays empty for the overwhelming majority, and
`clearAllState(id:)` clears it. Default is promotion on, for folded and hidden
plugins only.

Reachable from two places, because the two moments differ: Plugin Manager (the
deliberate, "I know this one is broken" moment) and a row in the promoted
plugin's own menu next to "Restart Plugin" (the "stop shouting at me" moment,
where the user actually is). Turning it off while promoted immediately
de-escalates to the resting placement.

### 4. A promoted item explains itself

Nothing new to build: `renderError` already builds the error menu — message,
"Show error output…", "Restart Plugin". A promoted plugin shows exactly that,
so a user who has never seen the plugin before still learns what failed and how
to act. The one added row is §3's opt-out.

### 5. Disabled and widget-only plugins never promote

A disabled plugin does not run, so it has no attention state. A
`<vee.surface>widget` plugin has no `StatusItemController`
(`PluginCoordinator.swift:111`) and therefore no placement to escalate; its
failures stay the widget's business.

## Risks / Trade-offs

- [A promoted item appears and shifts its neighbours] → the 60s damping is the
  whole mitigation, plus position memory (`autosaveName`) so a plugin that
  promotes repeatedly always returns to the same slot rather than walking
  across the bar.
- [A permanently broken plugin permanently occupies a slot] → the per-plugin
  opt-out is reachable from the promoted item itself, one click from where the
  user is looking.
- [60s is a guess] → it is one injectable constant in one place, and both
  directions share it; changing it later is a one-line change with tests that
  do not hard-code it.
- [Users may read promotion as Vee rearranging their bar on a whim] → the
  promoted item shows the error surface immediately, so the reason is visible
  the moment the item is; and it never changes what the user stored.

## Open Questions

- Should a plugin promoted from `hidden` also badge the home item's glyph
  (i.e. count toward the error roll-up) or only appear as a row? Leaning yes —
  it is the same signal the roll-up exists to give — but it makes a hidden
  plugin's failure change Vee's own icon, which is worth watching in QA.
