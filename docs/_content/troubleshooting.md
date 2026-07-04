# Troubleshooting

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
- **PATH differences:** a GUI app may see a narrower `PATH` than your interactive shell. If a plugin works in Terminal but not in Vee, use the tool's **absolute path** in the plugin (e.g. `/opt/homebrew/bin/jq` instead of `jq`), or set the `PATH` explicitly at the top of the script.
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

## Still stuck?

- Reveal the plugin in Finder from the Plugin Manager and read its source.
- Run it directly in Terminal to isolate app-vs-script issues.
- File an issue with the plugin's output and your macOS version at [github.com/navbytes/vee](https://github.com/navbytes/vee).
