---
title: "Debugging and testing plugins"
description: "Preview, watch, and lint a Vee plugin without installing it: vee render, vee show, vee dev, and vee lint, plus execution timeouts, exit codes, and the Debug console."
sidebar:
  label: "Debugging & testing"
  order: 11
head:
  - tag: link
    attrs:
      rel: "alternate"
      type: "text/markdown"
      href: "/guide/debugging.md"
      title: "Markdown source"
  - tag: title
    content: "Debugging and testing plugins — Vee docs"
---
Vee's authoring tools run without the app, without installing anything into your
plugins folder, and against Vee's real parser — so what you see in the terminal is
what the menu bar would build. This page is the workflow: preview a plugin, watch
it re-render as you save, catch authoring mistakes, and work out why a plugin is
misbehaving.

The four commands, shortest feedback loop last:

| Command | Use it when |
|---------|-------------|
| `vee render <plugin>` | You want to see the parsed menu tree once. |
| `vee show <plugin>` | You want a live terminal view on the plugin's own cadence. |
| `vee dev <path>` | You are actively editing — it re-runs on **every save**. |
| `vee lint <plugin>` | You want the authoring mistakes called out, in CI or in your editor. |

For the full subcommand list and flags, see [CLI and URL
actions](cli-and-urls.md#the-vee-command-line-tool).

## `vee render`

Renders exactly what Vee would show, so you can see a plugin's output — text
**or** JSON protocol — without installing it:

```sh
$ vee render ./cpu.5s.sh
CPU 12%  [sfimage=cpu]
---
Top processes  [href=https://example.com/procs]
───
Refresh  [refresh]
```

Parse diagnostics (unknown params, malformed lines) and a non-zero exit, a
timeout, or anything on stderr are surfaced too — it's the fastest way to answer
"why doesn't my plugin look right?".

## `vee show`

Where `vee render` prints one static tree, `vee show` is a live view of what the
plugin's menu-bar dropdown would look like — rendered natively in your terminal.
It re-runs the plugin on the cadence encoded in its filename and repaints, so you
can edit a script and watch the result without ever installing it into the menu
bar:

```sh
$ vee show ./cpu.10s.sh      # or an installed plugin by name: vee show cpu
```

The dropdown is rendered the way a terminal can: `color=`/ANSI as real color,
`progress=` as a Unicode block gauge (`████████░░░░ 72%`), `sparkline=` as a
block sparkline (`▁▂▃▅▇█`), and `toggle=`/`slider=` as inline state. The things a
terminal can't draw — SF Symbols and base64 images — are shown by name (`[cpu]`,
`[img]`) rather than dropped. A status line reports the plugin's cadence and last
exit code; parse diagnostics and stderr surface below, exactly like `vee render`.

Press **`r`** to refresh now and **`q`** (or `Ctrl-C`) to quit. A plugin with no
interval token in its filename (`.manual`) simply renders once and waits for `r`.

Flags: `--once` prints a single frame instead of watching (also what happens when
stdout is piped); `--no-color` disables ANSI color (as does a `NO_COLOR`
environment variable or a non-TTY stdout); `--dir DIR` sets the folder a plugin
*name* is resolved against.

`vee show` is a view, not a controller — it displays a row's action (with a small
trailing glyph: `↗` link, `$` shell, `⟳` refresh, `⌘` Shortcut) but does not fire
it. Activating items, the interactive control popovers, and the embedded WebView
remain the menu bar's job.

## `vee dev`

Where `vee show` re-runs on the plugin's *own* cadence — so an edit to a 5-minute
plugin appears five minutes later — `vee dev` re-runs on **save**. Put it in a
split terminal beside your editor and the loop is: edit, save, see it.

```sh
$ vee dev ./cpu.10s.sh
```

Each save re-runs the file and repaints the status line, the parsed menu tree,
and any lint findings. A save that breaks the script repaints with the exit code
and stderr and **keeps watching** — the loop does not exit over a typo. `r`
re-runs now, `q` quits.

### `--text`: preview a menu without running anything

`vee dev --text <path>` treats the file as plugin *output* rather than a program.
Nothing is executed, so the file needs no execute bit and no shebang, and a save
carries no risk of running code:

```sh
$ cat menu.txt
CPU 42% | color=red
---
Open dashboard | href=https://example.com

$ vee dev --text menu.txt
```

This is how to design a menu's *shape* before writing the script that produces
it — and, as the next section explains, it is the only mode in which an editor
can put a diagnostic on the right line.

### `--push`: see the real thing in the menu bar

A terminal shows structure; only Vee can show Vee's render. `vee dev --push` also
sends each save to the running app as a real status item, with **no file written
to your plugins folder**:

```sh
$ vee dev --push ./cpu.10s.sh
```

The item updates in place on each save and disappears when you quit. It is
opt-in — plain `vee dev` never touches your menu bar. If Vee is not running it is
started in the background (without stealing focus), and the loop says so.

One limitation, stated plainly: a pushed preview travels over the
`setephemeralplugin` URL action, and because any web page can open a `vee://`
URL, Vee strips `shell=`/`bash=` actions from ephemeral content. Those rows still
*appear* in the preview so you can confirm you wrote them correctly, but clicking
one does nothing. The loop prints a note when your menu contains one. To test an
executable action, install the plugin normally.

## `vee lint`

Catches the common authoring mistakes before you ship — the quoting bugs the
[JSON output format](json-output.md) sidesteps entirely, and a retired-SDK
import that can no longer run (see the [migration guide](sdk.md)):

```sh
$ vee lint ./broken.5s.sh
Lint findings:
  warning [line 3]: value for 'tooltip' contains a space but isn't quoted; wrap it in quotes (e.g. tooltip="a b")
  warning [line 4]: unknown parameter 'frobnicate'
```

`vee lint` exits `1` when it finds anything, so you can wire it into a
pre-commit hook or CI. A plugin that fails to run at all — a missing
interpreter, a crash before it prints anything — is itself a finding: there is
no output to lint, so reporting it clean would be the wrong answer. A
[streaming](plugin-authoring.md#streaming) plugin is the exception: lint runs it
as a one-shot, so hitting the execution timeout is how it always ends and is not
reported.

### Diagnostics in your editor (`--format compact`)

`--format compact` emits `path:line:col: severity: message` — the shape VS Code,
vim, and emacs already parse — so findings become inline diagnostics with no
Vee-specific editor extension:

```sh
$ vee lint --text --format compact menu.txt
menu.txt:1:1: warning: unknown parameter 'colour'
menu.txt:4:1: warning: value for 'color' contains a space but isn't quoted; wrap it in quotes (e.g. color="a b")
```

VS Code — add to `.vscode/tasks.json`:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "vee lint",
      "type": "shell",
      "command": "vee lint --text --format compact ${file}",
      "problemMatcher": {
        "owner": "vee",
        "fileLocation": ["autoDetect", "${workspaceFolder}"],
        "pattern": {
          "regexp": "^(.*):(\\d+):(\\d+):\\s+(warning|error):\\s+(.*)$",
          "file": 1, "line": 2, "column": 3, "severity": 4, "message": 5
        }
      }
    }
  ]
}
```

vim — `:set errorformat=%f:%l:%c:\ %t%*[^:]:\ %m` then `:cexpr system('vee lint --text --format compact ' . expand('%'))`.

### Which file a finding names, and why

**Lint runs over a plugin's output, not its source.** That distinction decides
what a line number can honestly refer to:

| Mode | What is linted | Path in compact output | In your editor |
|------|----------------|------------------------|----------------|
| `--text` | the file itself | the real path | diagnostics land on the correct line |
| default (executed) | the script's stdout | `<stdout>` | listed, but never placed on a line |

A script emitting fifty rows from one `echo` inside a loop makes the
output-line → source-line mapping many-to-one and unrecoverable. Naming the
script would put squiggles on lines that have nothing wrong with them, so
executed-script findings are attributed to `<stdout>`, which resolves to no file.
You still see every finding; your editor just does not mark an innocent line.

If you want squiggles that land exactly, lint the protocol text with `--text`.

## Execution timeouts

A plugin run is killed after **30 seconds** by default, and the menu shows the
plugin as errored. Long-running work needs either a longer timeout or a different
shape:

- Raise the limit for one plugin with `<vee.timeout>`, which accepts a plain
  number of seconds or a duration token (`ms`/`s`/`m`/`h`/`d`) and is clamped to
  1s–1h:

  ```sh
  # <vee.timeout>2m</vee.timeout>
  ```

- If the work is genuinely unbounded, make the plugin *streaming* instead — see
  [Streaming](plugin-authoring.md#streaming). A streaming plugin is not subject to
  the one-shot timeout, because it is expected to keep running and keep printing.

A plugin that regularly approaches its timeout is usually better off caching: do
the slow work on a long interval, write the result to
`SWIFTBAR_PLUGIN_CACHE_PATH`, and have the fast plugin read it.

## "No module named 'vee'" / "Cannot find module '@navbytes/vee'"

The three official SDKs are retired — see the **[SDK migration guide](sdk.md)**
for the full story. Short version:

```
$ python3 my-plugin.py
ModuleNotFoundError: No module named 'vee'
```

- **A `vee.py`/`vee.ts` file sits beside the plugin?** It keeps resolving —
  Python checks the script's own directory first, and a relative `./vee.ts`
  names a file directly. `vee lint` flags the import as a warning (a frozen
  copy, but working).
- **No sibling file anywhere?** The import cannot resolve at all — Vee no
  longer puts a copy on the interpreter's path. `vee lint` flags this as an
  error. Port the plugin to print the [JSON output format](json-output.md)
  directly; the migration guide has a before/after example.

## Exit codes and standard error

- **Exit code 0** — normal. Whatever the plugin printed to standard output is
  parsed and rendered.
- **Non-zero exit** — Vee marks the plugin as errored and surfaces it in the menu
  and the Debug console. Any output the plugin *did* print is still parsed
  best-effort, so a partial menu is better than a blank one.
- **Standard error** — never parsed as menu output. It is captured and shown in
  the Debug console, which makes it the right place to write your own debug
  tracing: it will not corrupt the menu. The exception is a **streaming** plugin,
  whose standard error is discarded rather than captured — if you are debugging
  one, print your tracing somewhere you can read it instead.

`vee dev` reports all three on every save and keeps watching, so a script that
breaks does not end the loop.

### Output is capped at 8 MB, and at 2000 lines

Standard output and standard error are each captured up to **8 MB**; beyond that
the rest is discarded. When it happens you get an `Output truncated at 8 MB`
diagnostic in the Debug console rather than silence. The cap is orders of
magnitude beyond any real menu, so hitting it almost always means a plugin is
printing something it did not mean to — a log, a file dump, an unbounded loop.

A second cap applies to what becomes menu rows: **2000 lines**. Every row is a
real menu item with a real view, so a plugin stuck in a loop takes the UI down
long before it exhausts the byte cap. Truncation is reported as a diagnostic, never
silent. Both numbers are set far past usable rather than tuned — an `NSMenu` is a
scrolling column, and nobody finds anything in its two-thousandth row. Submenu
*depth* has its own limit of 64.

## The Debug console

The app keeps a per-plugin Debug console — the last run's standard output,
standard error, exit status, and every parse diagnostic Vee produced while reading
the output. Open it from the Plugin Manager for the plugin you are investigating.

Use it when the terminal tools disagree with the menu bar: the console shows the
run Vee actually performed, including the environment it injected, which is the
usual explanation for "it works in my shell but not in Vee" (see
[Troubleshooting](troubleshooting.md#command-not-found--a-dependency-or-interpreter-is-missing)).

## See also

- [CLI and URL actions](cli-and-urls.md) — the full subcommand and flag reference, plus `vee new` and `vee search`.
- [Troubleshooting](troubleshooting.md) — symptoms and fixes when a plugin does not appear, errors, or times out.
- [Plugin authoring reference](plugin-authoring.md) — the output format the tools on this page parse.
- [SDK migration guide](sdk.md) — porting a plugin off the retired official SDKs.
