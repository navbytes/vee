---
title: "Getting started with Vee"
description: "Install Vee, write your first plugin, and learn where plugins live. A native macOS menu-bar script runner, xbar and SwiftBar compatible."
sidebar:
  label: "Getting started"
  order: 1
head:
  - tag: link
    attrs:
      rel: "alternate"
      type: "text/markdown"
      href: "/guide/getting-started.md"
      title: "Markdown source"
  - tag: title
    content: "Getting started with Vee — Vee docs"
---
Vee is a native macOS menu-bar script runner. It runs plugins — any executable, in any language — on a schedule and renders their standard output as menu-bar titles and dropdown menus. It is a fast, leak-free successor to [xbar](https://github.com/matryer/xbar) and [SwiftBar](https://github.com/swiftbar/SwiftBar), and it runs their plugins unchanged.

## Requirements

- macOS 26 or later (Vee uses the newest AppKit/SwiftUI APIs and the Liquid Glass UI).
- Apple Silicon (arm64). Intel Macs are not supported.

## Install

Vee is distributed as a Developer-ID-signed and notarized app **outside** the Mac App Store.

Vee's binary is both the menu-bar app and the `vee` CLI, so installing gets you
both.

**Homebrew (recommended):**

```sh
brew install --cask navbytes/tap/vee
```

Puts `Vee.app` in `/Applications` and `vee` on your PATH. `brew upgrade --cask vee`
picks up new releases automatically.

**Or one line, without Homebrew:**

```sh
curl -fsSL https://vee.navbytes.io/install.sh | bash
```

Same result, and re-running it upgrades in place.

The installer takes three options, so you are not stuck with its defaults. Pass
them after `bash -s --`:

```sh
# Install per-user instead of system-wide
curl -fsSL https://vee.navbytes.io/install.sh | bash -s -- --app-dir ~/Applications

# Put the CLI somewhere else on your PATH
curl -fsSL https://vee.navbytes.io/install.sh | bash -s -- --bin-dir /opt/homebrew/bin

# Pin a specific release rather than the latest
curl -fsSL https://vee.navbytes.io/install.sh | bash -s -- --version v0.2.0
```

| Option | Environment | Default |
| ------ | ----------- | ------- |
| `--app-dir DIR` | `VEE_APP_DIR` | `/Applications` |
| `--bin-dir DIR` | `VEE_BIN_DIR` | first writable of `~/.local/bin`, `/usr/local/bin` |
| `--version TAG` | `VEE_VERSION` | the latest release |

> **Not** `VEE_APP_DIR=… curl … | bash`. That sets the variable for `curl`, not
> for the `bash` reading the script, so it is silently ignored. Use a flag, or
> `export` the variable first.

**Just the CLI, via [mise](https://mise.jdx.dev):**

```sh
mise use github:navbytes/vee
```

The CLI only — mise puts binaries on your PATH and does not install GUI apps.
Use it when you want `vee` pinned per-project, or on a machine that only needs
the tooling.

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

To use a different folder (for example, an existing SwiftBar plugins directory), open the **Plugin Manager** and choose **Choose Folder**. See [Migrating from SwiftBar/xbar](migrating-from-swiftbar.md) if you already have a plugins folder. Switching folders leaves the old folder's plugins — and their saved settings and Keychain secrets — untouched, so you can point Vee back at it later and find everything as you left it.

Not everything in the folder is treated as a plugin. Vee skips hidden files, editor backups (`plugin.sh~`, `#plugin.sh#`), subdirectories (a `disabled/` folder is a common way to park plugins), the vendored SDK (`vee.ts`/`vee.py`), obvious document and data files by extension (`.md`, `.json`, `.png`, …), and extensionless project files by name (`README`, `LICENSE`, `Makefile`, `Dockerfile`, and similar) — so keeping the folder under version control doesn't put your README in the menu bar. A file with an extension is unaffected: a plugin genuinely named `readme.10s.sh` still loads.

## Write your first plugin

A plugin is just an executable file whose name encodes how often Vee re-runs it. The pattern is `name.INTERVAL.ext`, where the interval is a number plus a unit: `s` (seconds), `m` (minutes), `h` (hours), `d` (days), or `ms` (milliseconds).

The example below prints the xbar/SwiftBar text protocol, which every plugin can use and which keeps existing xbar/SwiftBar plugins working unchanged. For a plugin you're starting from scratch, printing the [structured-JSON format](json-output.md) (`{"vee":1,…}`) instead is recommended — typed values and no `|`-param escaping. Download [`plugins/showcase/kitchen-sink.1m.sh`](https://raw.githubusercontent.com/navbytes/vee/main/plugins/showcase/kitchen-sink.1m.sh) to see one file that exercises the whole JSON format:

```sh
curl -o ~/Library/Application\ Support/Vee/plugins/kitchen-sink.1m.sh \
  https://raw.githubusercontent.com/navbytes/vee/main/plugins/showcase/kitchen-sink.1m.sh
chmod +x ~/Library/Application\ Support/Vee/plugins/kitchen-sink.1m.sh
```

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

## Widgets (on your desktop / Notification Center)

Vee ships two WidgetKit widgets and a Control Center control, in addition to the
menu bar:

- **Vee Plugins** — a status tile for your plugins. Long-press the widget →
  **Edit Widget** to choose *which* plugins it shows (leave it empty to show all).
  At the small size it renders one plugin as a dashboard tile — its SF Symbol,
  its value in the plugin's color, and a live gauge (`progress=`) or trend chart
  (`sparkline=`) when the plugin publishes one — with a freshness caption. The
  medium/large sizes show an enriched row per plugin.
- **Vee Health** — an at-a-glance roll-up: "All healthy" or "N failing", with the
  failing plugins called out. It's the one view the menu bar can't give you.
- **Refresh Vee** (Control Center) — re-runs every plugin; launches Vee first if
  it isn't running.

Add them from the desktop (right-click → **Edit Widgets**) or Notification
Center. Widgets update when a plugin's output changes; because the system meters
how often widgets refresh, they suit slow-moving values (disk, battery, weather,
build/sync status) rather than per-second counters — those stay best in the menu
bar. The "updated N ago" caption reflects when the plugin last ran.

By default a widget tile is a scrape of the menu-bar line — automatic, no
changes needed. A plugin can opt into a **richer** tile instead: real data
(a stat, gauge, trend, list, or KPI board) on its own refresh cadence, with
up to two action buttons (refresh / open a link / run a Shortcut), via
`<vee.surface>both</vee.surface>` and a JSON "card" printed when Vee invokes
it with `VEE_TARGET=widget`. A plugin can also be **widget-only** —
`<vee.surface>widget</vee.surface>` gives it no menu-bar presence at all, just
a widget feed. See [Widgets](widgets.md) for the full
contract.

## Next steps

- [Plugin authoring reference](plugin-authoring.md) — the full output format, params, metadata, SF Symbols, ANSI, Markdown, streaming, and cron.
- [Preferences](preferences.md) — let a plugin declare typed settings that Vee turns into a form.
- [Trust model](trust-model.md) — how plugins declare what they access.
- [Widgets](widgets.md) — the full widget surface contract, card schema, and layout tree.
- [Debugging and testing plugins](debugging.md) — preview a plugin, watch it re-render on save, and lint it.
- [Plugin SDKs](sdk.md) — build plugins with typed builders (TypeScript, Python, or Go) instead of hand-formatting text.
- [JSON output format](json-output.md) — the structured-JSON format, recommended for new plugins.
