## Why

Writing a Vee plugin has no feedback loop. To see what a script produces you
either run it and read raw protocol text by eye, drop it into the plugins folder
and click the status item, or open the Debug console and press "Run again" after
every edit. `vee show` gets closest — it re-runs live and renders the dropdown —
but it re-runs on the *plugin's own interval*, not on save, so a 5-minute plugin
shows you your edit five minutes later.

Vee already owns every part needed to close this: `PluginExecutor` runs the
script, `OutputParser` parses it, `TreeRenderer` prints the tree, `Linter`
reports authoring mistakes with line numbers, and `setephemeralplugin` renders
arbitrary protocol text as a real native status item with no file on disk. What
is missing is a command that ties them to **file save**.

Authors also get no help from their editor. `vee lint` prints
`  error [line 12]: …`, which no editor can parse, so findings never become
squiggles — even though every editor in common use (VS Code's `problemMatcher`,
vim's `errorformat`, emacs compilation-mode) reads the standard
`path:line:col: severity: message` shape for free.

## What Changes

A **`vee dev <path>`** watch loop, plus the two smaller changes that make it and
the existing app feel immediate.

- **`vee dev <path>`** watches one file and, on every save, re-runs it, prints
  the parsed menu tree and any lint findings, and repaints. Run it in an editor's
  split terminal and the loop is: edit, save, see it.
- **`vee dev --text <path>`** treats the file as protocol text and **does not
  execute it**. This is how a menu's shape gets authored directly — instantly, with
  no process spawn and no arbitrary code run — and it is the mode in which lint
  line numbers refer to lines the author can actually see and fix.
- **`vee dev --push`** additionally renders each save as a **real native status
  item** through the existing ephemeral path, so the terminal shows structure
  while the menu bar shows Vee's true render. Opt-in: `vee dev` never adds a
  status item to the user's menu bar unless asked.
- **`vee lint --format=compact`** emits `path:line:col: severity: message`, which
  editors turn into inline diagnostics with no plugin and no extension.
- **Prompt in-place edit detection.** `PluginDirectoryWatcher` catches an edit to
  an already-installed plugin only via a **15-second poll**, because the vnode
  source it uses fires on directory-entry add/remove/rename, not on a write to an
  existing file. An author editing an installed plugin waits up to 15 seconds to
  see a change. This closes that regardless of how the editor writes the file.

Honest limitation, surfaced rather than hidden: **`vee lint` line numbers index
the plugin's stdout, not its source.** A loop emitting 50 rows from one `echo`
makes that mapping many-to-one and unrecoverable. So in script mode compact
output names a `<stdout>` pseudo-path — no editor will map it onto a wrong source
line — while `--text` mode names the real file, where source line and output line
are the same and squiggles land exactly right.

Non-goals, recorded so they are not re-proposed:

- **A VS Code extension.** Its irreducible value over this change is completions
  and syntax highlighting for a protocol-text file type. Everything else — preview,
  rerun on save, load into Vee, squiggles — this change delivers to *every* editor,
  with no marketplace listing, no `PATH` dependency, and no second release cadence.
- **A second parser or menu renderer outside Swift.** `VeePluginFormat` stays the
  single source of truth; anything that renders a menu shells out to `vee`.
- **A `.vee` file type**, TextMate grammar, or language server. `--text` gets the
  behavior with none of the registration surface. Revisit only if authors ask.
- **`--format=json`.** Nothing consumes it until an extension exists.
- **A trusted preview channel.** `--push` reuses `setephemeralplugin`, which
  strips `shell=`/`bash=` because any web page can open that URL. A pushed
  preview therefore shows executable rows but cannot fire them. Documented as a
  limitation; a trusted channel is its own change with its own security design.
- **An editor inside Vee.** Authors already have one.

## Capabilities

### New Capabilities
- `plugin-dev-loop`: the save-driven authoring loop — what `vee dev` watches,
  runs, renders, and pushes; how `--text` differs from script mode; and the
  editor-parseable diagnostic format.

### Modified Capabilities
<!-- No existing spec files under openspec/specs/ yet; the watcher change is
     covered as a requirement of the new capability above. -->

## Impact

- **New**: `Sources/VeeCLI/DevLoop.swift` (the watch loop), a file-watch seam,
  and compact diagnostic formatting.
- **Modified**: `Sources/VeeCLI/VeeCLI.swift` (dispatch `dev`, `--format` on
  `lint`, usage text), `Sources/VeeRuntime/PluginDirectoryWatcher.swift`
  (in-place edit detection).
- **Reused unchanged**: `PluginExecutor`, `OutputParser`, `TreeRenderer`,
  `Linter`, `LiveView`'s terminal handling, `setephemeralplugin`.
- **Docs**: `docs/_content/plugin-authoring.md` (the loop),
  `docs/_content/cli-and-urls.md` (`vee dev`, `--format`), `README.md`,
  `CHANGELOG.md`.
- **Dependencies**: none added. No new target, no third-party code.
