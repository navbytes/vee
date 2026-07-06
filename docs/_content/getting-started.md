# Getting started with Vee

Vee is a native macOS menu-bar script runner. It runs plugins — any executable, in any language — on a schedule and renders their standard output as menu-bar titles and dropdown menus. It is a fast, leak-free successor to [xbar](https://github.com/matryer/xbar) and [SwiftBar](https://github.com/swiftbar/SwiftBar), and it runs their plugins unchanged.

## Requirements

- macOS 26 or later (Vee uses the newest AppKit/SwiftUI APIs and the Liquid Glass UI).
- Apple Silicon (arm64). Intel Macs are not supported.

## Install

Vee is distributed as a Developer-ID-signed and notarized app **outside** the Mac App Store.

**Homebrew (recommended):**

```sh
brew tap navbytes/vee https://github.com/navbytes/vee
brew install --cask vee
```

`brew upgrade --cask vee` picks up new releases automatically.

**Or download directly:**

1. Download the latest `Vee.app` (inside a `.zip`) from the [GitHub Releases](https://github.com/navbytes/vee/releases) page.
2. Drag `Vee.app` into `/Applications`.
3. Launch it.

### First launch

Because Vee ships outside the App Store, the first launch goes through Gatekeeper. Vee is notarized, so a normal double-click should just work. If macOS shows an "unidentified developer" prompt, right-click (or Control-click) `Vee.app` and choose **Open**, then confirm. See [Troubleshooting](troubleshooting.md) if it is blocked.

### The menu-bar icon

Once running, Vee lives in the menu bar. With no plugins installed you will see the Vee icon; open it to reach **Discover**, the **Plugin Manager**, **Settings**, and **Refresh all**. As you add plugins, each one renders its own menu-bar item.

## Where plugins live

Vee looks for plugins in a folder on disk. The default location is:

```
~/Library/Application Support/Vee/plugins
```

To use a different folder (for example, an existing SwiftBar plugins directory), open the **Plugin Manager** and choose **Choose Folder**. See [Migrating from SwiftBar/xbar](migrating-from-swiftbar.md) if you already have a plugins folder.

## Write your first plugin

A plugin is just an executable file whose name encodes how often Vee re-runs it. The pattern is `name.INTERVAL.ext`, where the interval is a number plus a unit: `s` (seconds), `m` (minutes), `h` (hours), `d` (days), or `ms` (milliseconds).

Vee creates the plugins folder on first launch. If you haven't launched Vee yet, create it first:

```sh
mkdir -p ~/Library/Application\ Support/Vee/plugins
```

Then create `hello.5s.sh` in your plugins folder:

```sh
#!/bin/bash
echo "Hello 👋"
echo "---"
echo "It works!"
echo "Refresh | refresh=true"
```

- The first line before `---` is the **menu-bar title**.
- Everything after `---` is the **dropdown**.
- `refresh=true` makes that item re-run the plugin when clicked.

Make it executable:

```sh
chmod +x ~/Library/Application\ Support/Vee/plugins/hello.5s.sh
```

The `.5s` in the filename tells Vee to re-run it every 5 seconds. Vee detects the new file automatically; if it does not appear, use **Refresh all** from the menu.

## Refresh, enable, and disable

- **Refresh** a single plugin from the top of its dropdown, or **Refresh all** from the Vee menu.
- **Enable / disable** any plugin in the **Plugin Manager** — a disabled plugin stays on disk but is not run or shown.
- Plugins can also trigger a refresh themselves via URL actions — see [CLI and URL actions](cli-and-urls.md).

## Next steps

- [Plugin authoring reference](plugin-authoring.md) — the full output format, params, metadata, SF Symbols, ANSI, Markdown, streaming, and cron.
- [Preferences](preferences.md) — let a plugin declare typed settings that Vee turns into a form.
- [Trust model](trust-model.md) — how plugins declare what they access.
- [Plugin SDKs](sdk.md) — build plugins with typed builders (TypeScript, Python, or Go) instead of hand-formatting text.
- [JSON output format](json-output.md) — the optional structured-JSON alternative to the text protocol.
