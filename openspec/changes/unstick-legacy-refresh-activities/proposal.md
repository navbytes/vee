## Why

Vee cannot be quit on an affected install: killing it, or choosing Quit, is
followed by launchd relaunching it within moments. Observed on a real machine —
the app's launchd job carries an active `com.apple.xpc.activity` event channel
and reports `immediate reason = launch job demand`.

The cause is known and already documented (`VeeRuntime/LegacyBackgroundActivity.swift`):
earlier versions drove long-interval (≥10 min) refreshes with
`NSBackgroundActivityScheduler`, which registers a repeating, launch-on-demand
XPC activity against Vee's own launchd job. The registration lives in launchd,
not in the app, so it survives every update.

The existing unstick logic cannot reach it. `LegacyBackgroundActivity.clear` is
called from `PluginCoordinator.start()` — once per **currently loaded** plugin —
and the identifier it clears is derived from that plugin's ID. When the plugin
that registered the activity has since been deleted or renamed, its identifier
is never constructed and the activity is never invalidated. On the machine this
was found on, the installed plugins are `caffeine.30s.sh`, `clipboard.swift`,
and `litellm-cost.90s.js`: none is ≥10 min, so nothing currently loaded can
clear anything, and the app stays un-quittable indefinitely.

## What Changes

- **Remember every plugin ID Vee has ever loaded**, persisted in preferences, and
  clear legacy activity identifiers for all of them at launch — not only for the
  plugins present right now. A plugin deleted before the fix shipped is exactly
  the case that is currently unreachable.
- **Clear once at startup rather than per-plugin-start**, so the sweep does not
  depend on any plugin loading successfully. A plugin that fails to start, is
  disabled, or lives in a folder the user has since pointed away from must not
  keep the app pinned.
- **Surface the condition when it is detected**, so a user whose app will not
  quit learns why instead of assuming Vee is broken. Silent recovery is right
  for the sweep; silent *failure* to recover is what left this undiagnosed.
- **Do not add a new scheduling mechanism.** `NSBackgroundActivityScheduler` is
  deliberately unused; this change only removes registrations it left behind.

## Capabilities

### New Capabilities

- `app-quit-integrity`: quitting Vee is final — the app does not return on its
  own, and legacy launchd registrations that would relaunch it are cleared
  regardless of which plugins are currently installed.

## Impact

- `VeeRuntime/LegacyBackgroundActivity.swift`: gains a sweep over a set of known
  identifiers; the per-plugin entry point stays for the live case.
- `VeePreferences/AppPreferences.swift`: a new persisted set of every plugin ID
  seen.
- `VeeApp/AppController.swift`: runs the sweep at launch.
- `VeeApp/PluginCoordinator.swift`: records each plugin ID it starts; its
  existing `clear` call becomes redundant with the launch sweep and is removed.

**Not fixable from inside the app for an already-broken install where Vee is
never launched again** — the registration is in launchd. Users in that state
recover by launching the fixed build once. The recovery path must therefore run
on *every* launch, not once behind a "have I migrated?" flag.
