## Context

See `proposal.md` for motivation and `specs/product-state-integrity/spec.md` for observable behavior. The affected flows span SwiftUI models, the AppKit coordinator, ServiceManagement state, and pure catalog logic. Existing storage formats and recoverable Trash semantics must remain intact.

## Goals / Non-Goals

**Goals:**
- Make UI state transitions conditional on confirmed persistence or operating-system results.
- Keep the correction paths injectable and covered by focused failure tests.
- Preserve current successful-flow behavior and use existing dependencies.

**Non-Goals:**
- Define a new remote Store transport policy or provenance transaction model.
- Add first-run product orientation.
- Change process cancellation unless a deterministic test reproduces the suspected spawn race.
- Change plugin format, widget vocabulary, or storage schemas.

## Priority and behavior review

| Priority | Issue | Fix | Behavior change | Downside |
| --- | --- | --- | --- | --- |
| P1 | Variables can show Saved after a write fails | Return structured failures, retain edits, and gate success on all writes | Persistence failures become visible and retryable | A multi-field save can still be partial and must say so honestly |
| P1 | Failed Trash hides an installed plugin | Await a throwing deletion result before removing model/coordinator state | Failed deletion leaves the plugin visible and reports the error | Successful deletion can feel marginally less immediate |
| P2 | Store switches and remove buttons are unnamed | Add Store-specific accessibility labels | VoiceOver identifies each target and switch state | None visually |
| P2 | General can retain stale login-item state | Share or publish the authoritative result after each mutation | Menu and settings remain synchronized, including failures | Adds a small state propagation seam |
| P2 | Store edits can create duplicate identities | Apply add-time collision validation during update, excluding the edited ID | Conflicting edits fail without mutation | Some edits previously accepted are rejected |
| P2 | Manifest timestamp flags every unhashed plugin | Remove catalog-wide timestamp as plugin-specific update evidence | Unknown/unhashed versions no longer produce false updates | Real updates without per-plugin evidence may remain unknown |

## Decisions

### Persistence-first UI mutation
Operations that can fail will return a result to the view model/coordinator, and visible removal or success state will follow that result. This keeps the local model aligned with disk and system state. Optimistic mutation with rollback was rejected because rollback can miss coordinator and satellite state and creates a transient lie.

### Structured, non-secret save failures
Variable saving will collect field identity and a controlled error category without interpolating values or arbitrary underlying error text. Buffered form state remains owned by the editor until a complete retry succeeds. Failing fast was rejected because reporting all affected fields gives a more useful single retry cycle.

### Reuse canonical identity and version evidence
Store update will call the same effective-identity rule as add while excluding its own record. Update checks will use only hashes or timestamps attached to the plugin entry. Parallel validation rules were rejected because they can drift.

### Narrow state synchronization
Login-item mutation will publish the actual post-operation state through the existing application/UI ownership boundary. Polling on view appearance alone was rejected because it remains stale while the window is open.

## Risks / Trade-offs

- [Partial Variables persistence cannot be rolled back safely] -> Report partial failure explicitly, preserve all edits, and make retry idempotent.
- [Deletion callback ownership can outlive a row] -> Keep pending/error state at the manager model level and mutate the collection on success only.
- [ServiceManagement behavior is difficult to force in an app test] -> Isolate state/result propagation behind the existing manager boundary and unit-test the model path, then verify the native surface manually.
- [Removing timestamp fallback can hide legitimate updates] -> Prefer unknown/up-to-date over a false positive until the manifest supplies plugin-specific evidence.

## Migration Plan

No data migration is required. Land focused regression tests with each correction, run all SwiftPM and lint gates, generate the Xcode project, and build the app target. Rollback is a source revert with no persisted-state conversion.

## Deferred Findings

- Remote Store HTTPS/local file policy: security-relevant but requires an explicit compatibility policy and migration treatment.
- Install provenance transaction: requires a product decision for rollback versus degraded success and retry.
- First-run orientation: a usability hypothesis that needs clean-profile validation before implementation.
- Process-spawn cancellation: investigate with a controllable barrier; leave behavior unchanged unless the regression is deterministic.

The cancellation timebox found no existing spawn-injection seam: `posix_spawn` runs synchronously inside `ProcessRun.start()`, so a barrier test would first require changing production runtime structure. The existing delayed-cancellation integration test cannot target the PID-publication window. This remains inconclusive and no runtime change is included.

## Verification Notes

The state-changing paths are covered with injected stores, Trash behavior, and login-item results, and the unsigned native app target builds successfully. The production app was not launched for visual or VoiceOver proof because launch reads and can mutate standard preferences, Keychain, and login-item state; `VEE_PLUGINS_DIR` alone does not isolate those stores. The Store controls use native `Toggle` state plus explicit target-specific accessibility labels, but Accessibility Inspector verification remains a safe-harness follow-up.
