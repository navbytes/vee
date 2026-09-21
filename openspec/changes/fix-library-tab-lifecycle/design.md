## Context

`AppController.makeLibraryModel` currently snapshots manager rows and Variables groups, while `LibraryWindow.show` replaces the hosting root on every menu route. The retained Discover model separately captures its install directory. Runtime reloads replace coordinators but do not publish a refreshed inventory to those open-window models. Per-plugin Settings has a parallel save path that suppresses preference errors.

The production app cannot be launched safely for this work because `VEE_PLUGINS_DIR` does not isolate standard defaults, Keychain, Store state, or the real login item. Verification therefore uses injected stores/directories and view-model or native test-host coverage without production-profile mutation.

## Goals / Non-Goals

**Goals:**

- Give one owner responsibility for the active Library model and its directory generation.
- Derive Installed and Variables updates from one inventory snapshot and preserve compatible drafts.
- Keep directory switches transactional from the Library user's perspective.
- Reuse the controlled, value-redacted save semantics established by the aggregate Variables editor.

**Non-Goals:**

- Redesign Library navigation or visual styling.
- Change plugin execution, Store registry persistence, or plugin format.
- Add Debug running feedback or change the empty Settings segment.
- Change stale plugin-detail behavior unless a deterministic regression test proves it during implementation.

## Audit decisions

| Priority | Issue | Fix | Observable behavior | Downside |
| --- | --- | --- | --- | --- |
| P1 | Menu routes replace the Library model | Retain one model per open-window session; route by assigning `section` | Unsaved tab state survives ⌘M, ⌘D, and ⌘, | Requires explicit session-close ownership instead of implicit SwiftUI replacement |
| P1 | Reloads leave Installed and Variables stale | Build one inventory snapshot and reconcile both models after effective reload | Installs and file/header changes appear across tabs immediately | More model update code and cancellation/generation checks |
| P1 | Folder changes leave panes on different directories | Confirm draft discard when needed, then rebuild/rebind the session from one new-directory snapshot | All panes and Discover installs move together; cancel preserves old state | Directory changes may add one confirmation step |
| P1 | Per-plugin Settings suppresses write failures | Return a structured save result and close/refresh only on full success | Failed values stay editable and the user sees plugin/field context without secrets | Standalone window flow needs an error state instead of unconditional dismissal |
| P2 | Store trash deletes a token immediately | Add a Store-named destructive confirmation mentioning token deletion | Cancel is lossless; confirm removes the selected Store/token | Adds one click to intentional removal |
| P2 | Three root panes lack titles | Apply existing section names as navigation titles | Clear, consistent toolbar and accessibility context | Minimal extra view modifiers |
| Deferred | Debug action feedback and empty Settings segment | Separate follow-up | No behavior change in this scope | Known polish gaps remain |
| Deferred unless proven | Detail models can outlive coordinator replacement | First add deterministic generation/reload coverage | Fix only with reproducible stale-detail evidence | Potential stale detail remains documented if the test cannot reproduce it |

## Decisions

### Retain the Library model at the app/window boundary

`AppController` will retain the active `LibraryModel`, and `LibraryWindow` will expose a close callback so the model is released when the window session ends. Opening an already active Library changes `section` and focuses the existing window. This keeps drafts and modal state intact. Replacing the root view on each route was rejected because every child model and sheet state is destroyed.

### Reconcile from a generation-checked inventory snapshot

Factor the current plugin discovery, manager-row inputs, and variable aggregation into one directory-tagged snapshot. After runtime reload reaches its effective inventory, asynchronously build presentation data and apply it only if the directory/generation still matches. `PluginManagerModel` replaces rows from the snapshot. `VariablesEditorModel` reconciles by plugin ID and declaration name: retained identities keep buffered values, additions load persisted/default values, removals are dropped. Independent per-tab reloads were rejected because they can publish different filesystem moments.

### Treat a folder switch as a destructive context transition

Before calling the existing directory switch, inspect whether Variables or any retained per-plugin Settings model differs from its loaded baseline, including a typed but unapplied hotkey combination. If dirty, require an explicit discard confirmation. A pending Discover fetch/trust/install blocks the transition, and the old browser also validates its target before publishing a prompt and before writing. On confirmation, cancel/obsolete pending old-generation row work, close old-folder Settings windows, switch runtime state, rebuild only the directory-bound manager, Variables, and Discover state, update General's directory, and publish the binding together. The Stores model and other app-global General state remain retained. Drafts never cross directories because equal plugin IDs can represent different files or Keychain identities.

### Share save-outcome semantics, not UI state

Per-plugin Settings will expose the same controlled failure shape and all-values-success rule as Variables. A small shared value-persistence outcome/helper is acceptable if it shortens duplicate logic; the two view models keep their own presentation state. Raw errors and values never reach UI strings.

### Keep P2 presentation fixes local

Store removal confirmation belongs in the Store row/view and calls the existing removal method only after confirmation. Navigation titles use the existing `LibrarySection` labels. Neither change alters persistence APIs.

## Risks / Trade-offs

- [A stale async snapshot overwrites a newer folder or inventory] → Tag work with a monotonically increasing generation and reject mismatches on apply.
- [Reconciliation overwrites a user's draft] → Preserve values only for unchanged plugin/field identities and test add/remove/header-edit cases explicitly.
- [Folder switch partially updates the session] → Build the new binding before publishing it and keep cancellation on the old binding.
- [Watcher churn causes unnecessary parsing] → Reconcile only after an effective reload and keep existing coalescing/generation behavior.
- [A shared save helper expands scope] → Share only the structured outcome/persistence loop when it reduces code; avoid a new storage abstraction.

## Migration Plan

No persisted-data migration is required. Land model tests first, then lifecycle ownership and inventory reconciliation, then the bounded Settings and P2 presentation fixes. Rollback is the code revert; existing user data formats remain unchanged.
