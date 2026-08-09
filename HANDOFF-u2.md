# HANDOFF — runtime/lifecycle fixes (u2)

Branch: `fix/runtime-lifecycle`. Worktree: `/Users/naveen/repos/vee/.claude/worktrees/agent-a2cd3c8e6797e7574`.

## Fix 1 — reload spawns a duplicate live subprocess

**Root cause:** `PluginCoordinator.refresh()`/`refreshWidget()` wrapped their
async work in a fire-and-forget `Task {}` with no stored handle, so
`stop()` (called by `AppController.reload()` right before building the
replacement coordinator) had nothing to cancel. Even if it had a handle,
`SystemProcessRunner.run(_:)` used bare `withCheckedThrowingContinuation`,
which Swift Task cancellation does not observe — cancelling the Task would
have stopped waiting but never touched the already-spawned child.

**Fix (two layers, both needed):**
- `Sources/VeeApp/PluginCoordinator.swift`: added `refreshTask`/
  `refreshWidgetTask` stored properties, assigned at each `Task { ... }`
  call site, cancelled (and nilled) in `stop()`. The existing
  `guard self?.stopped != true` still suppresses stale UI/publish from a
  cancelled run.
- `Sources/VeeRuntime/SystemProcessRunner.swift`: `run(_:)` now wraps the
  continuation in `withTaskCancellationHandler`; `onCancel` calls a new
  `ProcessRun.cancelIfRunning()`, which shares `enforceTimeout`'s
  SIGTERM→SIGKILL-via-`killpg` escalation (refactored into
  `terminateGroup(markTimedOut:)`) rather than duplicating it. This is the
  root-cause fix: it also closes fix 4's "quit doesn't kill in-flight
  children" for free, since `applicationWillTerminate` already calls
  `coordinator.stop()` on every plugin.

**Tests:**
- `Tests/VeeAppTests/PluginCoordinatorRefreshOverlapTests.swift` —
  `PluginCoordinatorStopCancelsRefreshTests` (2 tests): a `SlowRunner` fake
  polls `Task.isCancelled`; asserts `stop()` makes it observe cancellation
  for both the menu-mode and widget-mode refresh Task, and that no further
  run starts afterward.
- `Tests/VeeRuntimeTests/ProcessRunnerIntegrationTests.swift` —
  `testCancellingAwaitingTaskTerminatesChild`: cancels the Task awaiting a
  real `sh -c "echo $$; sleep 30"`, asserts the printed pid is actually dead
  (`kill(pid, 0) == -1 && errno == ESRCH`) and the call returns in <5s, not 30s.

## Fix 2 — streaming session flushes stale buffer after cancel

One line: `StreamingSession.runLoop`'s post-loop `accumulator.flush()` is now
gated on `!Task.isCancelled`, mirroring the existing check right below it.

**Test:** `Tests/VeeRuntimeTests/StreamingTests.swift` —
`StreamingSessionCancelFlushTests`: a hand-driven `AsyncThrowingStream` (via a
captured `Continuation`) yields one separator-less line, `stop()` is called,
then the stream is finished; asserts `onUpdate` was never invoked. Verified
this fails without the fix (reverted the guard locally, test failed;
re-applied, passed) before finalizing.

## Fix 3 — detached actions never time out

`SystemProcessRunner` gained `defaultDetachedTimeout: TimeInterval = 120`
(configurable init param) and `ProcessRun.start()` now always arms the
timeout (`invocation.timeout ?? defaultTimeout`) instead of only when one was
explicitly passed. This is a one-guard, root-cause fix: `AppActionDispatcher`
(shell=/bash=/shortcut= menu actions) and `AppController.runShortcut`
(widget-card shortcut button) both build `ProcessInvocation` with no
`timeout`, both are out of my edit scope or several files away — fixing the
shared runner covers every caller without touching them. Plugin refreshes and
streaming plugins are unaffected: the former already always resolves an
explicit timeout before reaching here; the latter never goes through
`SystemProcessRunner` at all (`SystemStreamingRunner` is a separate type).

**Test:** `testNilTimeoutFallsBackToConfiguredDefault` — `SystemProcessRunner
(defaultDetachedTimeout: 0.3)` run against `sleep 10`, asserts `timedOut` and
<3s wall time.

## Fix 4 — quit / fd-reuse race

- **Quit kills in-flight children:** now true as a consequence of Fix 1 —
  `applicationWillTerminate` already calls `coordinator.stop()` on every
  plugin, and `stop()` now actually cancels+kills. Added a one-line comment
  at the call site explaining this. No new code/test beyond Fix 1's.
- **fd-reuse race (`ProcessRun.forceResumeIfStalled` / `StreamingProc.cancel`):**
  attempted the suggested `dup2`-to-`/dev/null` fix in both spots. **Reverted
  it** — the existing regression test
  `StreamingCancelEscalationTests.testFileDescriptorsStableAcrossRepeatedCancelOfIgnoredTerm`
  caught a real leak: a blocking `read()` already parked in the kernel is
  bound to the file description it resolved at syscall entry, not the
  fd-table slot, so `dup2`-ing the slot elsewhere does not wake it — only
  `close()` reliably does on this codebase's own (already-tested) assumption.
  With `dup2`, the parked reader thread (and everything it retains —
  `StreamingProc`, its `Pipe`) never got released: fd count went from stable
  to leaking ~1 fd per cancel cycle. Left both spots on `close()` with a
  `// ponytail:` note explaining the tradeoff and the real fix (move the
  reader off blocking raw `read()` onto non-blocking I/O behind a cancellable
  `kqueue`/`DispatchSource`), which is a bigger change than this ticket
  item warrants. Reported here per the brief's own escape hatch.

## Fix 5 — duplicate `vee.shortcut` fails silently

`PluginCoordinator` gained `hotkeyRegistrationError: String?` (set in
`registerHotKey()`'s `.use` branch when `GlobalHotKeys.shared.register`
returns `nil`, cleared at the top of `registerHotKey()` otherwise) and a
`displayError` computed property (`lastError ?? hotkeyRegistrationError`).
Kept separate from `lastError` deliberately: `lastError` is a *run* outcome
that a later successful refresh clears, and refreshes happen on a schedule —
reusing it would have made the collision flash briefly then vanish.
`AppController` now feeds `displayError` (not `lastError`) into both places
that already surface per-plugin errors to the Plugin Manager
(`managerRowInputs()` and the live `setError` push in `reload()`).

**Test:** `PluginCoordinatorDuplicateHotkeyTests` — two real coordinators
declaring the same obscure `<vee.shortcut>ctrl+opt+shift+cmd+f12</vee.shortcut>`;
asserts the first registers cleanly and the second's `displayError` is set.
Uses the real Carbon `RegisterEventHotKey` (no seam to fake it through) —
`XCTSkipIf` guards against an environment where hotkey registration doesn't
work at all, so it can't false-fail in a locked-down sandbox. Ran green
(not skipped) locally.

## Fix 6 — WidgetSnapshotPublisherTests CI flake (test-only)

Converted the 5 named tests' positive (should-happen) `settle()`-then-assert
blocks to the deadline-poll idiom already used elsewhere in the same file
(3s deadline, 20ms poll). Left the two identical-republish (negative) tests
(`testIdenticalRepublishSkipsWriteAndReloadBeforeFloors`,
`testIdenticalCardRepublishSkipsWriteAndReloadBeforeFloors`) entirely on
fixed sleeps, per the brief — there's no event to poll for a "this must NOT
happen" assertion. Zero production changes (`WidgetSnapshotPublisher.swift`
untouched, confirmed via `git diff --stat`).

## Deviation log

- fd-reuse `dup2` fix reverted (see Fix 4) — reported above, not silently dropped.
- Extended Fix 1's Task-storage/cancel guard to `refreshWidget()` as well as
  `refresh()` (the brief named only the latter) — same bug shape, same file,
  small diff; a `.both`/`.widget` plugin would otherwise still duplicate-run
  on reload.

## Incident during the session (informational, not a code issue)

Mid-session, an exploratory `git stash && <test> ; git stash pop` (used to
try to prove fail-before/pass-after on one fix) corrupted the working tree:
all in-progress edits vanished and an unrelated file (`Sources/VeeCatalog/
CatalogParser.swift`, not in this task's scope, not authored by me) appeared
modified. Reverted that stray file and redid the lost edits from scratch
before continuing. No `git stash` used afterward. Flagging in case the
sandbox's interaction with `git stash` is a known footgun worth a lesson.
