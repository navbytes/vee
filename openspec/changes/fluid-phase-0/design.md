## Context

Phase 0 of the plan in the Fluid design doc: one surface beyond the menu bar
(the panel), about a dozen view types, and helpers that run out of process.
The decisions it implements were made in the doc and its thread: Swift-only
plugins, a separate app that reuses Vee's ideas, helpers in their own
processes rather than loaded in-process, and ExtensionKit rather than
WebViews for richer UI (ExtensionKit is not part of phase 0).

## Decisions

- **Transport: newline-delimited JSON over the helper's stdin and stdout.**
  This replaces XPC in phase 0. Pipes work the same on Linux, so the
  supervisor is tested against real processes in CI, and inherited pipes still
  work under the App Sandbox. XPC stays an option if the sandbox spike shows a
  need for it.
- **The plugin's stdout is redirected to stderr at start-up.** The protocol
  uses a duplicated descriptor, so a stray `print` goes to the log.
- **Action ids come from content, not position**: `row/<key>/<title>`,
  `button/<title>`. A click that arrives after a re-render still finds its
  closure. Duplicate ids get a `#n` suffix.
- **`settled` after every handled message.** Hosts, `fluidctl` and the tests
  wait on it instead of sleeping.
- **The manifest is read by running `helper --manifest`.** The declaration is
  Swift and type-checked, with no separate file to drift.
- **Builds use a generated SwiftPM package per plugin, cached by content
  hash**, with compiler diagnostics mapped back to the plugin's file.

## Risks

- Ad-hoc signed sandboxed helpers and local ExtensionKit discovery are
  unverified. The app signs helpers only when `FLUID_SANDBOX=1` is set.
- The app target was written without a Mac to compile it on. The `Fluid`
  workflow's macOS job is the first compile.
