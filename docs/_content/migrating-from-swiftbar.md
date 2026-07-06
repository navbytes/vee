# Migrating from SwiftBar / xbar

Vee is designed as a drop-in successor to [SwiftBar](https://github.com/swiftbar/SwiftBar) and [xbar](https://github.com/matryer/xbar). Your existing plugins run unchanged — migration is usually just pointing Vee at the folder you already have.

## Point Vee at your existing plugins folder

1. Open Vee's **Plugin Manager**.
2. Click **Choose Folder** and select your existing SwiftBar or xbar plugins directory.
3. Vee discovers the plugins and starts running them on the intervals encoded in their filenames.

That is the whole migration. You do not need to rename, rewrite, or re-tag anything.

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
