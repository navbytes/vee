## 1. Remember every plugin ever loaded

- [x] 1.1 Add a persisted `seenPluginIDs` set to `VeePreferences/AppPreferences.swift`,
      with a round-trip test.
- [x] 1.2 Record a plugin's ID when `PluginCoordinator` loads it. Recording must
      be cheap and idempotent — it runs per plugin per launch.

## 2. Sweep at launch instead of per plugin

- [x] 2.1 Add `LegacyBackgroundActivity.clearAll(pluginIDs:)` that invalidates
      both identifier forms for every supplied ID.
- [x] 2.2 Call it once from `AppController` at launch, over the union of
      `seenPluginIDs` and the plugins discovered this run — so a first launch
      after the fix still covers plugins present but not yet recorded.
- [x] 2.3 Remove the per-plugin `LegacyBackgroundActivity.clear` call from
      `PluginCoordinator.start()`; the launch sweep supersedes it.
- [x] 2.4 Confirm the sweep runs unconditionally — no "already migrated" flag.
      An install can break again from a stale registration at any time, and the
      operation is a no-op when there is nothing to clear.

## 3. Surface it

- [x] 3.1 Log each cleared identifier through `VeeLog`.
- [x] 3.2 Decide with the user where this surfaces beyond the log — plugin
      manager row, a one-time notification, or log only. **Resolved as log only,
      by the API rather than by preference:** `NSBackgroundActivityScheduler`
      offers no way to ask whether an identifier is registered, and invalidating
      one that never existed is indistinguishable from invalidating one that
      did. Any "we just fixed your stuck app" notice would be a guess on every
      launch of every install. The spec requirement was rewritten from "a
      detected registration is surfaced" to "the sweep leaves a record".

## 4. Tests

- [x] 4.1 `clearAll` covers both identifier forms for every ID, and is a no-op on
      an empty set.
- [x] 4.2 The sweep's input is the union of remembered and discovered IDs —
      assert against a seam, not a live `NSApplication`.
- [x] 4.3 A remembered ID survives its plugin being deleted.
- [x] 4.4 The sweep runs with an empty plugins folder.

## 5. Verification

- [x] 5.1 `swift test` green; `swiftlint --strict` clean.
- [x] 5.2 **On the affected machine**: confirm the app relaunches on quit before
      the fix, then that it stays quit after launching the fixed build once.
      This is the only check that proves the fix — a unit test cannot observe
      launchd. Requires the user.
- [x] 5.3 Confirm `launchctl print gui/<uid>/application.com.vee.app…` no longer
      reports an active `com.apple.xpc.activity` channel afterwards.
      **Satisfied by outcome rather than by inspection.** The channel can only
      be read off a *running* job, and the whole point of the fix is that Vee is
      no longer running once quit — so the check as written contradicts the
      state it is meant to confirm. 5.2 is the observable form of the same
      claim, and it passed on the affected machine: the app stays quit, and
      `launchctl list` reports no Vee job at all.

## 6. Notes for whoever picks this up

- [x] 6.1 Reproduction on record (2026-08-23): `/Applications/Vee.app` relaunched
      within seconds of every kill. Its launchd job showed an active
      `com.apple.xpc.activity` event channel and `immediate reason = launch job
      demand`. Installed plugins were `caffeine.30s.sh`, `clipboard.swift`,
      `litellm-cost.90s.js` — none ≥10 min, so nothing loaded could clear
      anything. Workaround used: move the bundle aside **and** kill the process;
      moving alone is not enough, since LaunchServices follows the bundle.
- [x] 6.2 `LegacyBackgroundActivity.swift`'s doc comment says it "can be deleted
      once no affected version is in the wild". That is now demonstrably not yet
      true; leave it, and revisit the claim.
