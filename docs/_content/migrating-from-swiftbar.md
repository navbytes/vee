---
title: "Migrating from SwiftBar / xbar"
description: "Move to Vee from SwiftBar or xbar in one step: point it at your existing plugins folder. Full protocol compatibility, plus a trust layer and typed SDK."
sidebar:
  label: "Migrating from SwiftBar / xbar"
  order: 2
head:
  - tag: link
    attrs:
      rel: "alternate"
      type: "text/markdown"
      href: "/guide/migrating-from-swiftbar.md"
      title: "Markdown source"
  - tag: title
    content: "Migrating from SwiftBar / xbar — Vee docs"
---
Vee is designed as a drop-in successor to [SwiftBar](https://github.com/swiftbar/SwiftBar) and [xbar](https://github.com/matryer/xbar). Your existing plugins run unchanged — migration is usually just pointing Vee at the folder you already have.

## Point Vee at your existing plugins folder

1. Open Vee's **Plugin Manager**.
2. Click **Choose Folder** and select your existing SwiftBar or xbar plugins directory.
3. Vee discovers the plugins and starts running them on the intervals encoded in their filenames.

That is the whole migration. You do not need to rename, rewrite, or re-tag anything.

Everything below describes the xbar/SwiftBar text protocol your migrated plugins already use — it keeps working exactly as written. For **new** plugins, or ones you're rewriting anyway, Vee also understands a [structured-JSON output format](json-output.md) (`{"vee":1,…}`) that's easier to author than the text protocol's `|`-param quoting; see the [comparison](json-output.md#when-to-use-json-vs-the-text-protocol).

## What's compatible

Vee implements the xbar/SwiftBar plugin protocol, so the things you already rely on keep working:

- **Filename refresh intervals** — `cpu.5s.sh`, `mail.10m.py`, `backup.1h.rb`, etc. Units: `ms`, `s`, `m`, `h`, `d`.
- **Menu format** — the title line(s), `---` to start the dropdown, and `--` prefixes for nested submenus.
- **Line parameters** — `| key=value` params such as `color`, `href`, `bash=`/`shell=` with `param0..N`, `terminal`, `refresh`, `size`, `font`, `length`, `alternate`, `disabled`, `key`, `image`, `templateImage`.
- **SwiftBar extensions** — `sfimage` (SF Symbols), `sfcolor`, `sfsize`, `symbolize`, `md`/`markdown`, `tooltip`, `checked`, `badge`, `ansi`, `emojize`.
- **Metadata headers** — `<xbar.title>`, `<xbar.desc>`, `<xbar.author>`, `<xbar.dependencies>`, `<xbar.var>`, and the `<swiftbar.*>` equivalents (schedule, type=streamable, environment, and more).
- **Streaming plugins** — `<swiftbar.type>streamable</swiftbar.type>` with `~~~` block separators.
- **Cron schedules** — `<swiftbar.schedule>`.
- **Injected environment variables** — Vee sets the xbar `XBARDarkMode` variable and the SwiftBar `SWIFTBAR*`, `SWIFTBAR_PLUGIN_*`, and `OS_*` variables, so plugins that read them behave the same.

See the [plugin authoring reference](plugin-authoring.md) for the full list.

## Compatibility matrix

The detail behind that list. **Vee** implements everything in the xbar and
SwiftBar columns, and adds a column of its own.

A ✓ in the **Vee-only** column means the feature does not exist in xbar or
SwiftBar. Those tools ignore parameters and metadata tags they do not recognise,
so a plugin that uses them still *runs* there — it just renders without the
enhancement. If you need one plugin to look right in all three, stay in the first
two columns.

### Line parameters

| Parameter | xbar | SwiftBar | Vee-only |
|---|:--:|:--:|:--:|
| `color`, `font`, `size`, `length`, `trim` | ✓ | ✓ | |
| `href` | ✓ | ✓ | |
| `shell` / `bash`, `param0…N`, `terminal` | ✓ | ✓ | |
| `refresh` | ✓ | ✓ | |
| `dropdown` | ✓ | ✓ | |
| `alternate` | ✓ | ✓ | |
| `disabled` | ✓ | ✓ | |
| `key` | ✓ | ✓ | |
| `image`, `templateImage` | ✓ | ✓ | |
| `ansi`, `emojize` | ✓ | ✓ | |
| `sfimage`, `sfcolor`, `sfsize`, `sfconfig` | | ✓ | |
| `symbolize` | | ✓ | |
| `md` / `markdown` | | ✓ | |
| `tooltip` | | ✓ | |
| `checked` | | ✓ | |
| `badge` | | ✓ | |
| `webview`, `webvieww`, `webviewh` | | ✓ | |
| `shortcut` (runs a macOS Shortcut) | | ✓ | |
| `header` — a real AppKit section header | | | ✓ |
| `sparkline` | | | ✓ |
| `progress`, `trackcolor`, `accessoryw`, `accessoryh` | | | ✓ |
| `pie`, `donut`, `stackedbar` | | | ✓ |
| `chartlabels`, `chartcolors` | | | ✓ |
| `toggle`, `slider` — interactive popover controls | | | ✓ |
| `accessory` — which edge an accessory anchors to | | | ✓ |

### Metadata headers

| Tag | xbar | SwiftBar | Vee-only |
|---|:--:|:--:|:--:|
| `<xbar.title>`, `<xbar.version>`, `<xbar.author>`, `<xbar.author.github>` | ✓ | ✓ | |
| `<xbar.desc>`, `<xbar.image>`, `<xbar.dependencies>`, `<xbar.abouturl>` | ✓ | ✓ | |
| `<xbar.var>` — typed preferences | ✓ | ✓ | |
| `<swiftbar.schedule>` — cron | | ✓ | |
| `<swiftbar.type>streamable</swiftbar.type>` | | ✓ | |
| `<swiftbar.runInBash>`, `<swiftbar.refreshOnOpen>` | | ✓ | |
| `<swiftbar.environment>` | | ✓ | |
| `<swiftbar.persistentWebView>` | | ✓ | |
| `<swiftbar.hideAbout>`, `hideRunInTerminal`, `hideLastUpdated`, `hideDisablePlugin`, `hideSwiftBar` | | ✓ | |
| `<vee.filter>` — searchable filter panel | | | ✓ |
| `<vee.shortcut>` — global hotkey | | | ✓ |
| `<vee.surface>` — [widget surface](widgets.md) | | | ✓ |
| `<vee.timeout>` — per-plugin execution timeout | | | ✓ |
| `<vee.capabilities>`, `<vee.network>`, `<vee.secrets>`, `<vee.filesystem.read>` / `<vee.filesystem.write>`, `<vee.exec>` — [trust declarations](trust-model.md) | | | ✓ |

Vee reads both the `<xbar.*>` and `<swiftbar.*>` spellings wherever they overlap,
and ignores any tag it does not recognise rather than erroring — so a plugin
written for a newer xbar or SwiftBar than Vee knows about still runs.

### Output formats

| Format | xbar | SwiftBar | Vee-only |
|---|:--:|:--:|:--:|
| The text protocol (`---`, `--`, `\| key=value`) | ✓ | ✓ | |
| Streaming with `~~~` separators | | ✓ | |
| [JSON output](json-output.md) (`{"vee": 1}`) | | | ✓ |
| [Widget cards](widgets.md) (`VEE_TARGET=widget`) | | | ✓ |

### Portability in one line

`<vee.*>` tags live inside comments, so they are inert everywhere else — a plugin
carrying trust declarations is still a perfectly ordinary xbar plugin. Vee-only
*line parameters* are the ones to think about: they degrade to nothing, so the
row still appears, just plain.

## What's different (and better)

- **Native and leak-free.** Vee is pure Swift/AppKit — the menu bar is a real `NSStatusItem`/`NSMenu`, with no embedded WebView. Subprocess output is drained incrementally and processes are timed out and killed, so long-running use does not leak memory the way an old WebView-based architecture can.
- **A trust/transparency layer.** Plugins can declare what they touch — network domains, filesystem paths, secrets, external binaries — with `<vee.*>` tags. Vee shows a plain-language summary before you install a catalog plugin and trust badges in the Manager. It is advisory, not a sandbox. See the [trust model](trust-model.md).
- **Discover.** A built-in browser over the shared [matryer/xbar-plugins](https://github.com/matryer/xbar-plugins) catalog, with trust chips and one-click install through the trust gate.
- **Auto-generated preference forms.** `<xbar.var>` declarations become a typed settings form; secret fields are masked and stored in the macOS Keychain. See [preferences](preferences.md).
- **Optional typed SDKs.** Zero-dependency SDKs for TypeScript, Python, and Go let you build plugins with `Menu`/`Section` builders instead of hand-formatting text. See the [SDK docs](sdk.md).

## A note for xbar users

xbar and SwiftBar share the same core plugin format, and Vee reads both dialects. If you are coming from xbar, everything above applies — point Vee at your xbar plugins folder and they run. Vee also injects xbar's `XBARDarkMode` environment variable for plugins that switch appearance based on it.

## Caveats

- **macOS 26+ only.** Vee uses the newest system APIs; earlier macOS versions are not supported.
- **Apple Silicon only.** Vee is arm64; there is no Intel build.
- **Interpreters still need to be installed.** As with SwiftBar, a Python/Ruby/Node plugin only runs if that interpreter is on your system. If a plugin declares `<xbar.dependencies>`, make sure those tools are present. See [Troubleshooting](troubleshooting.md).
- **Un-sandboxed by design.** Plugins run with your full user privileges. That is the same model as xbar/SwiftBar; Vee makes it more transparent but does not isolate plugins. Read the [trust model](trust-model.md) before installing plugins you do not trust.
