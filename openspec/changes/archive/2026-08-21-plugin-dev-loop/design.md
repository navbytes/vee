## Context

See `proposal.md` — Why. The relevant constraints:

- `VeeCLI` depends on `VeeCore`, `VeePluginFormat`, `VeeRuntime`, `VeeSearch`.
  **It does not link AppKit**, so nothing here may reach for `NSWorkspace`,
  `NSRunningApplication`, or any AppKit type.
- `LiveView` already establishes the house pattern for an interactive terminal
  loop: raw-mode stdin, alternate screen, `poll()`, signal handlers polled via
  `sig_atomic_t`, and all rendering delegated to pure code.
- `PluginDirectoryWatcher` watches the plugins *directory* with a vnode source
  and carries a 15-second wall-clock tick as a backstop, because a vnode source
  on a directory does not fire for a write to an existing entry inside it.
- Zero third-party dependencies, and no new target.

## Goals / Non-Goals

**Goals.** One file-watch primitive shared by the new loop and the existing
watcher. Event-driven throughout — no new polling. Every formatting and parsing
decision lands in a pure function that `VeeCLITests` can exercise without a TTY,
a process, or a running app.

**Non-Goals (design level).** No refactor of `LiveView`; the two loops share
technique, not code, because their wake conditions differ. No `--text` on
`render` — the flag earns its place on `dev` and `lint` and nowhere else yet. No
change to how diagnostics are *computed*; only to how they are attributed and
formatted.

## Decisions

### One `FileWatcher` primitive in `VeeRuntime`, two consumers

A new `VeeRuntime/FileWatcher.swift` watches a single path: a vnode source on
`.write`/`.extend`/`.rename`/`.delete`, a debounce, and — critically — an
**inode recheck** so an editor that saves by writing a temp file and renaming it
over the target does not leave the watcher pointed at a dead inode. That recheck
is exactly the technique `PluginDirectoryWatcher.sourceMatchesCurrentDirectory()`
already uses for the directory case; this generalizes it to a file.

Consumers: `vee dev` (one watcher on the watched file), and
`PluginDirectoryWatcher` (one watcher per enumerated plugin file).

*Alternative rejected:* lower the existing 15-second tick to ~1 second. A
one-line diff, but it converts a rare wakeup into a permanent 1 Hz directory
scan plus an `stat` per plugin, forever, in an app whose stated identity is
bounded resource use over long uptime. Wrong trade for a save-latency problem.

*Alternative rejected:* FSEvents. It handles subtrees and coalescing that a flat
plugins folder does not have, and the existing code deliberately chose vnode
sources over the FSEvents C API for that reason. No need to revisit.

### Per-file watches sit *beside* the directory watcher, not instead of it

The directory source still handles add/remove/rename; the tick still recovers a
deleted-and-recreated folder. Per-file watchers only add the missing signal, and
they call the same debounced `onChange`. `AppController.reload()` already no-ops
on an unchanged mtime signature, so a redundant notification costs nothing —
which is what makes layering safe rather than duplicative.

**File-descriptor budget.** One `O_EVTONLY` descriptor per plugin, in a process
that also opens pipes for every plugin run. Exhausting descriptors would break
plugin *execution*, not just watching, so per-file watches are capped (256) and
anything beyond the cap is left to the existing tick. Cheap insurance against a
loud failure mode.

### `vee dev` wakes on a self-pipe, not a short poll timeout

The loop has two wake sources: the file changing, and the author pressing a key.
`LiveView` polls stdin with a timeout equal to the refresh interval, but `dev`
has no interval to wait out. The watcher (running on its own dispatch queue)
writes one byte to a self-pipe; the loop `poll()`s stdin **and** the pipe's read
end and blocks indefinitely on both.

*Alternative rejected:* an atomic flag plus a ~100 ms stdin poll timeout. Simpler
to write, but it is a 10 Hz wakeup that exists only to discover nothing happened
— the same objection as lowering the tick, at higher frequency.

**EOF must quit, not repaint.** `poll()` reports a closed descriptor as readable
*every* time, so treating a zero-length read as "repaint" spins the loop at full
speed — re-running the author's script continuously — with no key left that could
stop it. Found by driving the loop on a real pty.

### `--text` selects the input mode, and that choice drives path attribution

`--text` means "the file already contains plugin output; do not execute it". It
is one branch at the single point where a path becomes raw output.

That branch also decides how findings are attributed, which is the whole reason
the mode matters beyond convenience:

| Mode | Raw output from | Compact-format path | Editor squiggles |
| --- | --- | --- | --- |
| script (default) | executing the file | `<stdout>` | listed, never placed on a line |
| `--text` | reading the file | the real path | land on the correct line |

Diagnostics are computed over a plugin's **output**. For an executed script the
output-line → source-line mapping is many-to-one and unrecoverable (one `echo` in
a loop emits many rows), so naming the script would place squiggles on lines that
have nothing wrong with them. `<stdout>` resolves to no file, so an editor lists
the finding in its problems view and marks nothing. Being unhelpful is acceptable;
being confidently wrong is not.

*Alternative rejected:* refuse `--format=compact` outright in script mode. More
obviously safe, but it discards findings the author can still act on by reading
them.

*Alternative rejected:* infer the mode from the execute bit. A `.sh` the author
forgot to `chmod +x` would be previewed as protocol text and render its own
shebang and source as menu rows — a baffling failure. An explicit flag cannot
misfire.

### Compact format is `path:line:col: severity: message`

The shape VS Code's `problemMatcher`, vim's `errorformat`, and emacs
compilation-mode all already parse. `ParseDiagnostic` carries no column, so the
column is always `1`; a diagnostic with no line is attributed to line `1` rather
than omitted, so no editor is handed an out-of-range line. Formatting is a pure
function in `VeeCLI`, unit-tested directly. The human-readable form stays the
default — existing output is byte-for-byte unchanged for anyone who does not pass
the flag.

### `--push` shells out to `/usr/bin/open -g`

`VeeCLI` cannot link AppKit, and `setephemeralplugin` already renders arbitrary
protocol text as a real status item with no file on disk. So the push is:
percent-encode the output via `URLComponents`, and run
`/usr/bin/open -g "vee://setephemeralplugin?…"` through the `ProcessRunning`
seam the CLI already injects — which also keeps the push testable with a fake
runner.

- **`-g`** so a background launch never steals focus from the editor.
- **Not running** → `open` launches Vee. That is the right outcome for someone
  developing a Vee plugin, but it is not silent: the loop says it started Vee.
  **Not installed** → `open` exits non-zero and the loop reports the push failed
  while the textual view carries on.
- **Stable key** `dev:<basename>` so each save updates one item instead of
  accumulating one per save.
- **Teardown**: a clean exit pushes empty content with `exitafter=1`. Every push
  also carries a long `exitafter` as a crash-safety net, so a `SIGKILL`ed loop
  cannot strand an item in the menu bar.
- **Size cap** (32 KB of encoded content). A URL argument is bounded by `ARG_MAX`
  and by LaunchServices, while plugin stdout is capped at 8 MB — so an oversized
  menu skips the push and says so, rather than failing opaquely.
- **Explicit percent-encoding**, not `URLComponents.queryItems`, whose escaping
  of `&` and `+` in values has historically been inconsistent — and a menu body is
  exactly the kind of text that contains both.

### Executable rows are visible in a preview but inert, and the loop says so

`showEphemeral` strips `shell=`/`bash=` because any web page can open that URL;
`--push` inherits that. Rather than let a row silently do nothing, the loop
prints a one-line note on the first push whose output contains an executable
action. A trusted channel is deliberately out of scope — it is a security design,
not plumbing.

## Risks / Trade-offs

- **Per-file watchers add descriptors and teardown paths to a component whose
  correctness is load-bearing.** → They are additive: the directory source and
  the tick are untouched, so a bug in the new layer degrades to today's behavior
  rather than breaking discovery. Capped at 256 descriptors.
- **`<stdout>` may render oddly in some editors' problem views.** → It resolves
  to no file, which is the point; the finding is still readable, and `--text`
  gives exact attribution when the author wants squiggles.
- **`--push` can launch Vee as a side effect of a dev command.** → `-g` prevents
  focus theft and the loop announces it.
- **A `SIGKILL`ed loop cannot run its teardown.** → The safety-net `exitafter`
  on every push bounds how long a stranded preview can live.
- **Two terminal loops (`LiveView`, `dev`) now use raw mode and the alt screen.**
  → Accepted duplication of ~30 lines of terminal setup. Unifying them would
  require parameterizing the wake condition, which is the only thing that
  actually differs; the abstraction would be larger than the duplication.

## Migration Plan

Purely additive. `vee dev` is a new subcommand; `--format` and `--text` are new
flags whose absence preserves today's behavior exactly. The watcher change alters
timing only, never which plugins are discovered. Rollback is removing the
subcommand and the per-file watch layer independently — neither is a prerequisite
of the other.
