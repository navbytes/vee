## Why

The consolidated Library window currently rebuilds independent tab models on menu routing and leaves them stale after installs, file changes, or a plugins-folder switch. That can discard unsaved Variables edits, show or write against the wrong folder, and report success when per-plugin settings were not persisted.

## What Changes

- Retain one Library model for the active window session and route menu actions by changing its selected section.
- Reconcile Installed and Variables from one current plugin-inventory snapshot after effective reloads, preserving dirty values for unchanged plugin/field identities.
- Rebind the whole Library session atomically when the plugins folder changes so Installed, Discover, Variables, and General all target the new directory, gating dirty aggregate and per-plugin drafts and invalidating pending installs.
- Make per-plugin Settings surface sidecar and Keychain write failures, retain edits, and close or refresh only after full success.
- Confirm custom Store removal before deleting the registry entry and saved token.
- Give Variables, Stores, and General consistent navigation titles.
- Keep Discover status and action labels readable at the Library window's default and minimum widths.
- Defer Debug run feedback, the empty Settings segment, and stale detail handling unless a deterministic detail regression test proves the lifecycle defect.

## Capabilities

### New Capabilities

- `library-session-integrity`: Defines coherent Library window routing, directory binding, live inventory reconciliation, truthful settings persistence, and safe destructive Store removal.

### Modified Capabilities

None.

## Impact

The change affects Library model ownership and routing in `VeeApp`, the Installed/Variables/Discover coordination paths in `VeeUI`, per-plugin preference save reporting, Store removal presentation, and focused unit/integration tests. It adds no dependency or plugin-format change and does not require launching the production app against user state.
