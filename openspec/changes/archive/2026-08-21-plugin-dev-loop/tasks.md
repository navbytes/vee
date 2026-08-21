## 1. File-watch primitive

- [x] 1.1 Add `Sources/VeeRuntime/FileWatcher.swift`: watch one path via a vnode source (`.write`/`.extend`/`.rename`/`.delete`), debounce notifications, and reopen on an inode change so an atomic-replace save keeps working. State confined to a private queue.
- [x] 1.2 Add `Tests/VeeRuntimeTests/FileWatcherTests.swift`: in-place write fires; atomic-replace (write temp + rename over) fires and keeps firing afterwards; rapid successive writes coalesce to fewer notifications than writes; `stop()` is idempotent and silences further events.

## 2. Prompt detection of edits to installed plugins

- [x] 2.1 In `PluginDirectoryWatcher`, add a per-plugin-file `FileWatcher` layer beside the existing directory source, all calling the same debounced `onChange`. Rebuild the set when the directory changes; cap at 256 watched files and leave the remainder to the existing tick.
- [x] 2.2 Keep the directory vnode source and the 15s tick untouched, so the new layer is purely additive and a failure degrades to today's behavior.
- [x] 2.3 Extend `Tests/VeeRuntimeTests` for the watcher: an in-place edit to an existing plugin notifies well before the tick interval; add/remove/rename still notify; a deleted-and-recreated directory still recovers; the file-count cap does not crash or leak descriptors.

## 3. Diagnostic formatting

- [x] 3.1 Add `Sources/VeeCLI/DiagnosticFormatter.swift`: a pure function rendering `[ParseDiagnostic]` in either the existing human form or compact `path:line:col: severity: message`. Column is always `1`; a line-less diagnostic is attributed to line `1`.
- [x] 3.2 Move `VeeCLI.format(_:)`'s human-form logic into it so both commands share one implementation and the default output is byte-for-byte unchanged.
- [x] 3.3 Add `Tests/VeeCLITests/DiagnosticFormatterTests.swift`: compact shape for error and warning; line-less diagnostic lands on line 1; empty input yields no lines; human form matches the current output exactly.

## 4. `--text` input mode

- [x] 4.1 Add a single seam that turns a path into raw plugin output, either by executing it (default) or by reading it (`--text`), returning the raw text plus the path to attribute diagnostics to (`<stdout>` when executed, the real path when read).
- [x] 4.2 Wire `--text` into `vee lint`, and `--format=compact|human` (default `human`) into `vee lint`.
- [x] 4.3 Add `Tests/VeeCLITests` coverage: `--text` does not execute the file (fake runner records no run); `--text` on a non-executable file with no shebang succeeds; compact output names the real path under `--text` and `<stdout>` without it.

## 5. `vee dev` watch loop

- [x] 5.1 Add `Sources/VeeCLI/DevLoop.swift`: alternate screen + raw-mode stdin following `LiveView`'s pattern, waking via `poll()` on stdin **and** a self-pipe written by the `FileWatcher`. Signal handling via `sig_atomic_t`, terminal state restored on every exit path.
- [x] 5.2 On each wake from the watcher: obtain raw output through the 4.1 seam, parse it, and repaint a frame with the run status (exit code / timeout / stderr present), the `TreeRenderer` tree, and lint findings in human form. Replace the frame, never append.
- [x] 5.3 Keep the loop alive across a failing run — a non-zero exit, a timeout, or a parse with diagnostics repaints and keeps watching.
- [x] 5.4 Keybindings: `q`/`Ctrl-C` quit, `r` re-run now. Repaint on `SIGWINCH`.
- [x] 5.5 Extract the frame body (status + tree + diagnostics for a given outcome and width) as a pure function so it is testable without a TTY, mirroring how `LiveView` delegates to `showBody`.
- [x] 5.6 Add `Tests/VeeCLITests/DevLoopTests.swift` over the pure frame function: clean run, non-zero exit, timeout, stderr present, diagnostics present, and `--text` mode all render the expected sections.

## 6. `--push` menu-bar preview

- [x] 6.1 Add a pure function building the `vee://setephemeralplugin` URL: key `dev:<basename>`, percent-encoded content via `URLComponents`, and a long safety-net `exitafter`. Return nil when encoded content exceeds the 32 KB cap.
- [x] 6.2 Invoke `/usr/bin/open -g <url>` through the injected `ProcessRunning` seam on each save when `--push` is set. Report a non-zero exit as "preview could not be shown" and continue the textual loop.
- [x] 6.3 Report a background launch of Vee in the frame rather than doing it silently.
- [x] 6.4 Print a one-line note on the first push whose parsed output contains a `shell=`/`bash=` action, stating that executable actions do not fire in a preview.
- [x] 6.5 On clean exit, push empty content with `exitafter=1` to tear the preview down. Never write to the plugins folder.
- [x] 6.6 Add `Tests/VeeCLITests` coverage with a fake runner: URL is built and encoded correctly for content containing `&`, `|`, `#`, and newlines; the key is stable across saves; oversized content skips the push; teardown is issued on clean exit; no push at all without `--push`.

## 7. CLI surface

- [x] 7.1 Dispatch `dev` in `VeeCLI.run` and add `vee dev <path> [--text] [--push] [--no-color]` plus `lint`'s `--text` / `--format` to `Usage.text`.
- [x] 7.2 Match the existing exit-code convention (`2` for usage errors, `1` for a failed run) and reject unknown flags with usage rather than ignoring them.
- [x] 7.3 Guard against entering the interactive loop when stdin is not a TTY, the way `runShow` does.
- [x] 7.4 Add `Tests/VeeCLITests` coverage for argument parsing: missing path, unknown flag, `--text` plus `--push` together, and that `dev` on a non-TTY does not enter the loop.

## 8. Docs and release notes

- [x] 8.1 Document the loop in `docs/_content/plugin-authoring.md`: `vee dev`, `--text` for authoring a menu's shape without executing anything, and running it in an editor's split terminal.
- [x] 8.2 Document `vee dev` and `lint --text` / `--format=compact` in `docs/_content/cli-and-urls.md`, including a copy-pasteable VS Code `tasks.json` `problemMatcher` and a vim `errorformat` line.
- [x] 8.3 State plainly in the docs that script-mode diagnostics index stdout and are therefore attributed to `<stdout>`, and that `--text` is the mode where squiggles land on the right line.
- [x] 8.4 State that a `--push` preview cannot fire executable actions, and why.
- [x] 8.5 Regenerate the affected `docs/guide/*.html` from `docs/_content` using the existing docs build.
- [x] 8.6 Update `README.md`'s command list and add a `CHANGELOG.md` entry.

## 9. Verification

- [x] 9.1 `swift build` and `swift test` clean.
- [x] 9.2 Manual: `vee dev` on a real plugin, driven on a pty — 4 repaints, a broken save surfaced `exit 4` + stderr + the lint diagnostic without exiting the loop, then recovery to `exit 0`, alt screen restored, clean exit.
- [x] 9.3 Manual: `vee dev --text` repaints with no process spawned, and the documented VS Code `problemMatcher` regex — JSON-decoded exactly as VS Code would — matches every line of real `--format compact` output and extracts the right groups.
- [x] 9.4 Manual: `vee dev --push` against the running Vee app — push succeeded, the shell-action note fired, no spurious launch announcement. Covered permanently by `DevPushRoundTripTests`, which runs the built URL through the app's real `URLActionRouter`.
- [x] 9.5 Manual: **Verified** against a dev-built app run with `VEE_PLUGINS_DIR` pointed at a throwaway folder (the installed `/Applications/Vee.app` was never modified). Probe plugin on a `1h` interval, so its own schedule cannot explain any re-run; it appends a timestamp per run. An in-place truncate+write (**identical inode before and after** — the exact event a directory vnode source cannot see) re-ran the plugin in **0.23s**. A burst of 8 rapid saves produced **1** run, not 8. A plugin added *after* launch, then edited in place, re-ran in **0.77s**.
