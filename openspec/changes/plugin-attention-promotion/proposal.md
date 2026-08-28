# Proposal: plugin-attention-promotion

## Why

`plugin-bar-placement` lets a user take a plugin out of the menu bar. That
makes a standing problem sharper: **placement goes stale exactly when it
matters.** A user folds the five plugins they rarely read, and the sixth — the
one that has been silently failing since Tuesday — is the one they needed to
see.

Today a folded plugin's failure reaches the bar as a warning glyph on a shared
icon that does not say *which* plugin
(`CompactMenuBarController.setEntryError`), and once `hidden` exists a failing
plugin has no signal at all. The information is already computed: the runtime
classifies every run, and `StatusItemController` already tracks whether the
plugin is currently in error. Nothing surfaces it proportionally.

## What Changes

- A plugin whose resting placement is `folded` or `hidden` is **temporarily
  escalated one rung** while it is failing, and returns when it recovers:
  - `hidden` → a row in Vee's home item (which badges, as it already does)
  - `folded` → its own menu-bar item
  - `own` → unchanged; it is already maximally visible and its glyph already
    swaps to the error symbol
- **Resting placement is never rewritten.** Promotion is an override computed
  on top of it; changing placement while promoted recomputes from the new
  resting value.
- **Attention is crash-derived only in this change**: the plugin is in the
  error state `StatusItemController` already tracks — a timeout, a non-zero
  exit with no usable output, or a spawn/stream failure. No new plugin
  vocabulary, no parser work, and so no `WidgetParity` or surface-parity ledger
  work.
- **Damped against flapping** by one symmetric constant: escalate after the
  plugin has been continuously failing for 60s, de-escalate after it has been
  continuously healthy for 60s. A plugin oscillating faster than that never
  earns 60s of health, so it stays visible — which is the correct outcome for a
  plugin that is genuinely unstable.
- **The user can stop it.** Per-plugin "don't promote this plugin", default on
  for folded and hidden plugins, reachable both from Plugin Manager and from
  the promoted plugin's own menu, next to the existing "Restart Plugin" row.
- A promoted item reuses the plugin's `autosaveName`, so it returns to the same
  slot every time rather than landing wherever a new item lands.

## Behaviour contract

The `openspec` CLI is not installed in this environment, so this change
declares `skip_specs: true` and carries no `specs/` deltas. `design.md` and the
acceptance checks in `tasks.md` are the authority.

## Impact

- **Depends on `plugin-bar-placement`** — it consumes that change's
  `BarPlacement` and its `reconcilePlacement()` seam. Land it after.
- `Sources/VeeApp/StatusItemController.swift` — an attention state fed from the
  two edges that already exist (`render(_:)` clears the error, `renderError`
  sets it), driving the same `reconcilePlacement()` transition.
- `Sources/VeePreferences/AppPreferences.swift` — the per-plugin promotion
  opt-out, stored as a departure from the default like the other per-plugin
  flags, and cleared by `clearAllState(id:)`.
- `Sources/VeeUI` — the opt-out in Plugin Manager rows.
- Docs site: what promotion does, and how to turn it off.

## Deferred

- **Author-declared alerts** (`alert=true` on a title line) for a *healthy*
  plugin that wants to shout — disk at 94%, build red. Needs new vocabulary,
  which touches `LineParams` and therefore `WidgetParity`, the generated
  ledger, and `docs/design/surface-parity.md`, and needs an answer for what the
  widget does with an alerting plugin. Separate change; this one deliberately
  does not block on it.
