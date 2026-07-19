# CLI and URL actions

Vee can be driven from the command line during development and controlled at runtime through URL actions. Plugins use those same URL schemes to trigger refreshes and post notifications.

## Running from source (`swift run vee`)

For development, run the menu-bar app straight from the SwiftPM package:

```sh
swift build          # build the libraries + dev executable
swift test           # run the test suites
swift run vee        # launch the menu-bar app for development
```

`swift run vee` starts the app so you can iterate on plugins and code without producing a full app bundle. See the project README for building the distributable, notarized `Vee.app`.

While developing you can point Vee at a specific plugins folder with an environment variable, which overrides the folder chosen in the UI:

```sh
VEE_PLUGINS_DIR=~/dev/my-plugins swift run vee
```

## The `vee` command-line tool

Running `vee` with no subcommand launches the menu-bar app (that's also what
happens when the bundled app is opened). Passing a subcommand instead gives you a
zero-install authoring loop that reuses Vee's real parser — no app, no GUI:

| Command | What it does |
|---------|--------------|
| `vee render <plugin>` | Runs the plugin and prints the parsed menu tree plus any parse diagnostics. |
| `vee show <plugin>` | Renders the plugin's dropdown in the terminal — color, block progress bars, and sparklines — and live-refreshes it on the plugin's own cadence. |
| `vee lint <plugin>` | Runs the plugin and reports problems: unknown params, a bare `\|` in a title, unquoted values containing spaces, and the parser's own diagnostics. Exits non-zero if anything is flagged. |
| `vee search <plugin> [query…]` | Runs the plugin, flattens its (nested) menu, and prints the items fuzzy-filtered and ranked by your query — each with its breadcrumb and the action it would fire. |
| `vee new [flags]` | Scaffolds a new plugin file with the right filename, header tags, and a working body. |

### `vee render`

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

### `vee show`

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

### `vee lint`

Catches the common authoring mistakes before you ship — especially the
quoting bugs the [SDKs](sdk.md) prevent by construction:

```sh
$ vee lint ./broken.5s.sh
Lint findings:
  warning [line 3]: value for 'tooltip' contains a space but isn't quoted; wrap it in quotes (e.g. tooltip="a b")
  warning [line 4]: unknown parameter 'frobnicate'
```

`vee lint` exits `1` when it finds anything, so you can wire it into a
pre-commit hook or CI.

### `vee new`

Scaffolds a ready-to-run plugin. Flags: `--lang ts|py|sh`, `--interval` (e.g.
`5s`, `10m`), `--name`, `--trust` (comma-separated capabilities, e.g.
`network,secrets`), and `--out DIR`. When run in a terminal with flags omitted,
it prompts.

```sh
$ vee new --lang sh --interval 30s --name weather --trust network --out ~/plugins
# writes ~/plugins/weather.30s.sh with <xbar.*> + <vee.*> headers and a working body
```

For `ts`/`py`, the generated body imports the corresponding [SDK](sdk.md) so a
scaffold doubles as a starting point for typed authoring.

### `vee search`

Flattens a plugin's whole menu tree — including nested submenus — and prints the
items fuzzy-filtered and ranked, so you can try the [searchable filter
panel](plugin-authoring.md#searchable-filter-panel)'s matching from the terminal
before installing anything. With no query it lists every activatable item.

```sh
$ vee search ./dev-dashboard.5m.sh retry
2 of 45 item(s) match "retry":
  #412 Fix retry backoff jitter  ⟨Repositories › orders › Pull Requests⟩  [href]
  feature/retry-jitter  ⟨Repositories › orders › Branches⟩  [shell]
```

Query words are ANDed and matched fuzzily (`gh` finds `GitHub`); a match on a
parent group's name still surfaces its children. Exits `1` when nothing matches
and `2` on a missing path, so it slots into scripts and CI too.

## URL actions

Vee registers two URL schemes: `vee://` and `swiftbar://`. The `swiftbar://` scheme is supported for compatibility, so plugins written for SwiftBar keep working. Both schemes accept the same actions.

The **action is the URL host**, and parameters come from the query string. The plugin name is passed as `name` (or `path`).

| Action | Description | Example |
|--------|-------------|---------|
| `refreshallplugins` (alias `refreshall`) | Re-run every plugin. | `vee://refreshallplugins` |
| `refreshplugin` | Re-run one plugin by name. | `vee://refreshplugin?name=cpu` |
| `enableplugin` | Enable a plugin. | `vee://enableplugin?name=cpu` |
| `disableplugin` | Disable a plugin. | `vee://disableplugin?name=cpu` |
| `toggleplugin` | Toggle a plugin's enabled state. | `vee://toggleplugin?name=cpu` |
| `addplugin` | Download and install a plugin from a URL. | `vee://addplugin?src=https://example.com/cpu.5s.sh` |
| `setephemeralplugin` | Show transient menu content in its own status item, with no file on disk (optionally auto-removed after `exitafter` seconds). | `vee://setephemeralplugin?name=build&content=Done&exitafter=5` |
| `notify` | Post a system notification. | `vee://notify?title=Done&subtitle=Build&body=Succeeded&href=https://example.com` |

The same URLs work with the `swiftbar://` scheme, e.g. `swiftbar://refreshplugin?name=cpu`.

### The `notify` action

`notify` posts a macOS notification. Its parameters:

- `title` — the notification title.
- `subtitle` — an optional subtitle.
- `body` — the notification body text.
- `href` — an optional URL to open when the notification is clicked. Scheme-filtered like every other Vee URL (`file:`/`javascript:` are ignored; `http(s)` and app deep links such as `vee://` are allowed).
- `plugin` — the originating plugin's id. When present, the alert becomes **actionable** — it gains **Re-run**, **Silence** (mute this plugin's alerts for the session), and **Open Log** buttons — and repeated alerts from the same plugin coalesce instead of stacking. Pass your own id with the injected `$VEE_PLUGIN_ID` variable.

```
vee://notify?title=Backup&subtitle=Nightly&body=Completed%20successfully&href=https://example.com
```

An **actionable** alert from a monitor plugin, tagged with its id so Re-run /
Silence / Open Log resolve back to it:

```bash
open "vee://notify?plugin=$VEE_PLUGIN_ID&title=Build%20failed&body=exit%201"
```

Remember to URL-encode parameter values that contain spaces or special characters.

## Triggering actions from a plugin

Because these are ordinary URLs, a plugin triggers them the same way it opens any link — either as an `href` on a menu item, or by opening the URL from the script.

**As a clickable menu item** (`href=`):

```bash
echo "Refresh now | href=vee://refreshplugin?name=cpu"
echo "Enable weather | href=vee://enableplugin?name=weather"
```

**From the script itself** (open the URL with `open`):

```bash
# Notify when a long task finishes
open "vee://notify?title=Build&body=Done"

# Force this plugin to re-render immediately
open "vee://refreshplugin?name=$VEE_PLUGIN_PATH"
```

Note that a menu item can also refresh the plugin without a URL at all, using the `refresh=true` line parameter:

```bash
echo "Refresh | refresh=true"
```

Use `refresh=true` for the common "re-run me" case; use the URL actions when a plugin needs to refresh, enable/disable, or toggle a *different* plugin, or to post a notification.

## See also

- [Plugin authoring reference](plugin-authoring.md#line-parameters) — the `href` and `refresh` parameters.
- [Plugin authoring reference](plugin-authoring.md#environment-variables-vee-injects) — `VEE_PLUGIN_PATH` and other injected variables.
