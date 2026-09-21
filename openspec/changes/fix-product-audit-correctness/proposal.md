## Why

Several settings and catalog flows currently report success or mutate visible state before persistence succeeds, which can mislead users about saved credentials, deleted plugins, login-item state, and available updates. The same audit found unnamed Store controls and duplicate Store identities that make common management tasks unreliable or inaccessible.

## What Changes

- Make Variables saving report persistence failures without discarding buffered edits or showing a false success state.
- Make plugin deletion remove Installed UI state only after moving the plugin to Trash succeeds, and expose failure for retry.
- Give Store enable and remove controls store-specific accessibility names.
- Keep the General launch-at-login control synchronized with menu-bar changes and the actual system result.
- Reject Store edits that collide with another Store's effective identity.
- Stop treating a manifest-wide timestamp as evidence that every unhashed plugin has an update.
- Investigate the process-spawn cancellation window, but change runtime behavior only if a deterministic regression test reproduces it.
- Record TLS policy, provenance transactions, and first-run orientation as deferred findings outside this defect-correction scope.

## Capabilities

### New Capabilities
- `product-state-integrity`: Honest persistence outcomes, coherent controls, accessible Store management, unique Store identities, and evidence-based update status.

### Modified Capabilities

None.

## Impact

The change affects `VeeUI`, `VeeApp`, `VeeCatalog`, and their focused test suites. It changes no plugin format, storage format, dependency, or release behavior; successful existing flows remain visually and functionally equivalent.
