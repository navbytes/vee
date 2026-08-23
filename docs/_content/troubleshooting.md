---
title: "Troubleshooting"
description: "Fix common Vee issues: a plugin not appearing, Gatekeeper blocks, timeouts, missing interpreters and PATH differences, and refreshes not happening."
sidebar:
  label: "Troubleshooting"
  order: 15
head:
  - tag: link
    attrs:
      rel: "alternate"
      type: "text/markdown"
      href: "/guide/troubleshooting.md"
      title: "Markdown source"
  - tag: title
    content: "Troubleshooting — Vee docs"
---
Common issues and how to fix them. If none of these help, open an issue at [github.com/navbytes/vee](https://github.com/navbytes/vee).

## A plugin doesn't appear in the menu bar

Work through these in order:

1. **Is it executable?** Vee runs plugins as programs. Mark the file executable:
   ```sh
   chmod +x ~/Library/Application\ Support/Vee/plugins/mine.5s.sh
   ```
   (If a file is not executable, Vee still tries its shebang interpreter and falls back to bash — but `chmod +x` is the reliable path.)
2. **Is it in the plugins folder?** The default is `~/Library/Application Support/Vee/plugins`. Confirm the folder Vee is using in the Plugin Manager (Choose Folder), and make sure the plugin is directly inside it.
3. **Is the filename valid?** The interval token must sit right before the extension: `cpu.5s.sh`, not `cpu.sh.5s`. A file like `cpu.sh` with no interval runs on demand, not on a timer.
4. **Is it enabled?** Check the Plugin Manager — a disabled plugin stays on disk but is not run or shown.
5. **Force a scan.** Use **Refresh all** from the Vee menu, or toggle the plugin off and on.

## "unidentified developer" / Gatekeeper blocks the app

Vee is notarized, so a normal double-click should work. If macOS still blocks it:

- Right-click (or Control-click) `Vee.app` in `/Applications` and choose **Open**, then confirm the dialog. macOS remembers the choice after the first time.
- Alternatively, open **System Settings → Privacy & Security**, scroll to the message about Vee being blocked, and click **Open Anyway**.

Make sure you downloaded `Vee.app` from the official [GitHub Releases](https://github.com/navbytes/vee/releases) page.

## A plugin errors or shows nothing useful

- **Run it in a terminal first.** A plugin is just a script — run it directly and read the output:
  ```sh
  ~/Library/Application\ Support/Vee/plugins/mine.5s.sh
  ```
  If it errors there, fix it there. Vee runs the plugin with your environment plus its own injected variables (see [authoring](plugin-authoring.md#environment-variables-vee-injects)).
- **Check the first line before `---`.** Only the text before the first `---` becomes the menu-bar title. If your title line is empty or errors, the menu-bar item looks blank.
- **Watch quoting.** Line parameters after `|` must be quoted when they contain spaces (`title="two words"`), and quotes inside values escaped (`\"`).

## A plugin times out

Vee runs each on-demand plugin with a timeout (30 seconds by default) and kills the process if it overruns. If your plugin does slow work (a slow network call, a heavy computation):

- Make it faster, or cache results between runs (use `SWIFTBAR_PLUGIN_CACHE_PATH` / `SWIFTBAR_PLUGIN_DATA_PATH`).
- If it is genuinely long-running and pushes continuous updates, make it a **streaming** plugin instead (`<swiftbar.type>streamable</swiftbar.type>` with `~~~` separators), which stays running rather than being re-invoked on a timer. See [Streaming](plugin-authoring.md#streaming).

## "command not found" / a dependency or interpreter is missing

Vee does not install your plugin's dependencies. If a plugin needs `python3`, `node`, `jq`, `gh`, etc., that tool must be installed and on the `PATH`.

- Check the plugin's `<xbar.dependencies>` header for what it needs.
- Verify the tool exists: `which python3`, `which jq`, and so on.
- **PATH:** Vee resolves your login shell's `PATH` at launch (running `$SHELL -ilc`) and adds the usual Homebrew locations, so tools installed via Homebrew, pyenv, asdf, or nvm are normally found just like in Terminal. If a tool is configured somewhere unusual (or only in a non-login shell rc file) and still isn't found, use its **absolute path** in the plugin (e.g. `/opt/homebrew/bin/jq`), or set `PATH` explicitly at the top of the script.
- For a script without a shebang and without the executable bit, Vee falls back to `/bin/bash`. Add a proper shebang (`#!/usr/bin/env python3`) so the right interpreter is used.

## Refreshes aren't happening

- **Confirm the interval.** The filename controls it: `weather.10m.sh` is every 10 minutes, `weather.sh` is on demand only.
- **Cron plugins** use `<swiftbar.schedule>` (5-field cron). Double-check the expression — an invalid field means it never fires.
- **Manual refresh** always works: the plugin's own dropdown has a refresh action if it prints one (`refresh=true`), and the Vee menu has **Refresh all**.
- Plugins can trigger refreshes via [URL actions](cli-and-urls.md) (`vee://refreshplugin?name=…`).

## Permissions (network, files, notifications)

Plugins run with your user privileges, so they generally have the access you do. A few things to know:

- **macOS privacy prompts.** The first time a plugin (through Vee) touches a protected area — Contacts, Calendar, files in protected folders, etc. — macOS may prompt. Grant access in **System Settings → Privacy & Security** if you trust the plugin.
- **Notifications.** For `vee://notify` to show alerts, allow notifications for Vee in **System Settings → Notifications**.
- The `<vee.*>` trust declarations are **advisory** — they describe what a plugin says it does, and Vee never blocks based on them. See the [trust model](trust-model.md).

## Diagnostics reference

Vee's parser is deliberately permissive: bad input degrades to a diagnostic and
a best-effort render, never a crash and never a blank menu. Those diagnostics
are collected per run and shown in the plugin's **Debug console** (Plugin
Manager → the plugin), and printed by
[`vee render` and `vee lint`](debugging.md).

Every one of them means *something you wrote was ignored or altered*, so an
empty diagnostics list is the goal.

### Line and parameter problems

| Diagnostic | What happened | Fix |
|---|---|---|
| `unknown parameter '…'` | A `key=` Vee does not recognise. The value is preserved but nothing renders from it. | Check the spelling against the [parameter table](plugin-authoring.md#line-parameters). |
| `duplicate parameter '…'` | The same key appeared twice on one line. | Remove one; the winner is not something to rely on. |
| `parameter '…' has no value` | A bare key with no `=value`. | Give it a value, or drop it. |
| `value for '…' contains a space but isn't quoted` | The value was cut short at the space. | Quote it: `tooltip="two words"`. |
| `stray '\|' in title text` | A later `\|` was read as the params delimiter and truncated the item. | Escape it as `\\|`, or let an [SDK](sdk.md) do the escaping. |
| `alternate item has no preceding item` | `alternate=true` on a line with nothing above it to be the alternate *of*. | Move it below the item it alternates with. |
| `paramN given without shell=/bash=` | Positional arguments with no command to pass them to. | Add `shell=`/`bash=`, or remove the params. |
| `submenu depth exceeded; truncated` | More than 64 levels of `--` nesting. | Flatten the menu — this is far past usable. |
| `submenu depth jumped; clamped to …` | A line nested more than one level deeper than its parent (e.g. `--` then `------`). | Add the intermediate level, or reduce the dashes. |

### Images

| Diagnostic | What happened | Fix |
|---|---|---|
| `image=/templateImage= is not valid base64; dropped` | The payload did not decode. | Re-encode; check for stray newlines in the base64. |
| `image=/templateImage= decodes to over 2097152 bytes; dropped` | Over the 2 MB image cap. | Shrink the image — menu icons need very few pixels. |

### Charts and gauges

| Diagnostic | What happened | Fix |
|---|---|---|
| `progress= expects a fraction (0..1) or 'value,max'` | The value did not parse. | Use `progress=0.72` or `progress=23,100`. |
| `pie=/donut=/stackedbar= expects a comma-separated list of non-negative numbers` | The list did not parse. | Use `pie=45,30,25`. |
| `… values must all be finite and non-negative` | A `NaN`, an infinity, or a negative share. | Clamp the values before printing them. |
| `… values sum to zero; nothing to chart` | Every share was `0`. | Skip the chart when there is no data, rather than emitting zeros. |
| `… has N segments; the last M were folded into 'Other'` | More than 8 segments. | Aggregate the tail yourself if you want to control the label. |
| `chartlabels=/chartcolors= given without pie=/donut=/stackedbar=` | Labels or colors with no chart to attach to. | Add the chart param, or remove them. |
| `chartcolors= has a malformed color; those segments use the default palette` | A color name or hex Vee could not read. | Check against the named colors, or use `#rrggbb`. |
| `accessory= expects 'leading' or 'trailing'` | Any other value. | Use one of the two. |
| `slider= expects 'min,max,value' with min < max` | Malformed or inverted bounds. | e.g. `slider=0,100,40`. |

### URLs

| Diagnostic | What happened | Fix |
|---|---|---|
| `href= has a missing or unsafe url; dropped` | The URL did not parse, or used a blocked scheme. Only `http`, `https`, and app deep links open — never `file:`, `javascript:`, and the like. | Use a web URL, or run a command with `shell=` instead. |
| `abouturl has a missing or unsafe url; dropped` | Same gate, on `<xbar.abouturl>`. | As above. |

### Widget cards

Only from a [widget-mode](widgets.md) run.

| Diagnostic | What happened | Fix |
|---|---|---|
| `widget output is not a JSON object` | `VEE_TARGET=widget` produced something that is not one JSON object. Vee falls back to scraping the menu text. | Print exactly one JSON object and nothing else. |
| `unknown widget template "…"; using stat` | A `template` outside the five. | Use `stat`, `gauge`, `trend`, `list`, or `board`. |
| `unknown widget status "…"; ignored` | A `status` outside the three. | Use `ok`, `warning`, or `error`. |
| `progress is not a finite number; dropped` / `progress N outside 0...1; clamped` | A bad or out-of-range gauge fill. | Clamp to `0…1` before printing. |
| `trend contained non-finite values; dropped` | A `NaN`/infinity in the series. | Filter the series first. |
| `href action "…" has a missing or unsafe url; dropped` | A card action's URL failed the scheme gate. | Use a web URL or an app deep link. |

### Widget layout trees

| Diagnostic | What happened | Fix |
|---|---|---|
| `unknown layout node type "…"` | A `type` outside the ten. The node renders as nothing. | Check it against the [node types](widgets.md#node-types). |
| `layout nested deeper than 8 levels; inner nodes dropped` | Past the depth cap. | Flatten the tree. |
| `layout has more than 64 nodes; extra nodes dropped` | Past the node cap. | Send less — a widget tile is small. |
| `layout text longer than 512 characters; truncated` | A very long `text` node. | Shorten it; it would not have fit anyway. |
| `layout sparkline longer than 256 points; truncated` | Too many series points. | Downsample before printing. |
| `layout sparkline contained non-finite values; dropped` / `layout gauge value is not finite; dropped` | A `NaN`/infinity. | Filter or clamp first. |

### Run-level

| Diagnostic | What happened | Fix |
|---|---|---|
| `Output truncated at 8 MB` | The plugin printed more than the capture cap. | Almost always accidental — a log or an unbounded loop reaching stdout. |

## Still stuck?

- Reveal the plugin in Finder from the Plugin Manager and read its source.
- Run it directly in Terminal to isolate app-vs-script issues.
- File an issue with the plugin's output and your macOS version at [github.com/navbytes/vee](https://github.com/navbytes/vee).
