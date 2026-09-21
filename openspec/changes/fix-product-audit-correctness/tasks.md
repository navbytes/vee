## 1. Persistence correctness

- [x] 1.1 Add failure-and-retry tests for Variables saves, including field identification, secret redaction, retained edits, and no false success
- [x] 1.2 Implement structured Variables save outcomes and persistent actionable UI errors
- [x] 1.3 Add deletion failure/success tests covering Installed row, runtime coordinator, and satellite state
- [x] 1.4 Make Trash failure preserve installed/runtime state and expose an actionable manager error

## 2. Control coherence and accessibility

- [x] 2.1 Add Store-specific accessibility names and verify switch state remains exposed
- [x] 2.2 Add tests for launch-at-login state propagation on successful and failed menu/settings mutations
- [x] 2.3 Implement a shared authoritative launch-at-login state update path without changing the user's real login item during tests

## 3. Catalog correctness

- [x] 3.1 Add a regression test for editing a Store into another Store's effective identity
- [x] 3.2 Reuse canonical duplicate-identity validation in Store update while excluding the edited record
- [x] 3.3 Add a regression test showing a catalog-wide timestamp alone cannot mark every unhashed plugin updated
- [x] 3.4 Remove manifest-wide timestamps from per-plugin update evidence while retaining hash and true entry-specific comparisons

## 4. Cancellation investigation

- [x] 4.1 Attempt a deterministic spawn-barrier regression test for cancellation before PID publication
- [x] 4.2 Change cancellation handling only if task 4.1 reliably fails on the current implementation; otherwise record the inconclusive finding without a runtime diff

## 5. Verification and review

- [x] 5.1 Run focused regression tests and the full `swift build`, `swift test`, and `swiftlint lint --strict` gate
- [x] 5.2 Generate the Xcode project and build the app target without signing
- [x] 5.3 Use an injected-state native harness for UI proof if feasible; otherwise document why launching the production app would mutate user state
- [x] 5.4 Obtain an independent review of the complete diff and resolve actionable findings
- [ ] 5.5 Open a draft pull request with the final behavior, verification evidence, and deferred findings
