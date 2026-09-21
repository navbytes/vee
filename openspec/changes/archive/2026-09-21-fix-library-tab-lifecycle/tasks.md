## 1. Active Library session

- [x] 1.1 Add regression coverage showing Installed, Discover, and General routes reuse one active Library model and preserve an unsaved Variables draft
- [x] 1.2 Retain one Library model for the open-window session, route by section mutation, and release it on window close

## 2. Inventory and directory coherence

- [x] 2.1 Add isolated-directory regressions for Discover install, external add/remove, and variable-header changes updating Installed and Variables together
- [x] 2.2 Add Variables reconciliation tests proving unchanged plugin/field drafts survive while added identities initialize and removed identities disappear
- [x] 2.3 Build and publish one generation-checked inventory snapshot to the active Installed and Variables models after effective reloads
- [x] 2.4 Add folder-switch regressions proving cancel preserves a dirty old-directory session and confirmation atomically rebinds General, Installed, Variables, and Discover
- [x] 2.5 Implement dirty-draft detection and an atomic directory transition that invalidates old asynchronous work and rebuilds every directory-bound submodel
- [x] 2.6 Attempt a deterministic test for an open plugin detail across coordinator replacement; fix generation invalidation or re-resolution only if the test proves stale behavior

## 3. Truthful per-plugin Settings saves

- [x] 3.1 Add injected sidecar and secret-store failure tests for in-pane and standalone Settings, covering retained values, controlled plugin/field errors, no refresh, and no dismissal
- [x] 3.2 Implement structured per-plugin save outcomes and allow refresh/dismissal only after every value persists successfully

## 4. Bounded P2 presentation fixes

- [x] 4.1 Add Store removal presentation tests for cancel, confirm, target naming, token-deletion copy, and accessible destructive action naming
- [x] 4.2 Require Store-named destructive confirmation before invoking the existing removal operation
- [x] 4.3 Add navigation-title coverage and expose Variables, Stores, and General through their existing section names
- [x] 4.4 Keep Discover status/action labels single-line at default and minimum Library widths and verify through the isolated native harness

## 5. Verification and review

- [x] 5.1 Run focused lifecycle, Settings, Store, and title regressions without production-profile state
- [x] 5.2 Run `swift build`, `swift test`, and `swiftlint lint --strict`
- [x] 5.3 Generate the Xcode project and build the unsigned app target
- [x] 5.4 Obtain independent code review and resolve actionable findings
- [x] 5.5 Record native UI proof only through an isolated injected-state harness; otherwise document the production-state limitation without visual claims
