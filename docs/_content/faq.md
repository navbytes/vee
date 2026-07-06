# FAQ

### Is Vee safe if plugins run un-sandboxed?

Plugins run as ordinary programs with your full user privileges — Vee does not sandbox them, and that is by design (a menu-bar script runner exists to run arbitrary scripts). The safety model is **transparency, not isolation**: plugins declare what they access with `<vee.*>` tags, and Vee shows a plain-language trust summary before you install and trust badges in the Manager. Treat a plugin like any other script you download: read the source of anything you do not trust. See the [trust model](trust-model.md) for the full picture.

### Will my existing SwiftBar or xbar plugins work?

Yes. Vee implements the xbar/SwiftBar plugin protocol — filenames, menus, params, metadata headers, streaming, cron, and the injected environment variables. Point Vee at your existing plugins folder (Plugin Manager → Choose Folder) and they run unchanged. See [Migrating from SwiftBar/xbar](migrating-from-swiftbar.md).

### What macOS version do I need?

macOS 26 or later. Vee uses the newest AppKit/SwiftUI APIs and the Liquid Glass UI, so earlier versions are not supported.

### Does it run on Intel Macs?

No. Vee is Apple Silicon (arm64) only. There is no Intel build.

### Why isn't Vee on the Mac App Store?

The App Store requires apps to be sandboxed, and that sandbox is incompatible with running arbitrary user plugins. Vee is instead distributed Developer-ID-signed and **notarized** outside the App Store, downloaded from GitHub Releases. This is the same reason xbar and SwiftBar are distributed outside the store.

### How is Vee different from SwiftBar?

Vee runs the same plugins, so it is a superset in practice, plus:

- **Native and leak-free** — pure Swift/AppKit with no embedded WebView in the menu, rigorous subprocess draining and timeouts, so long-running use does not leak memory.
- **A trust/transparency layer** — plugins declare their footprint and Vee surfaces it.
- **Discover** — a built-in catalog browser with one-click install through a trust gate.
- **Auto-generated preference forms** with Keychain-backed secrets.
- **Optional typed SDKs** for TypeScript, Python, and Go.

See [Migrating from SwiftBar/xbar](migrating-from-swiftbar.md).

### Does Vee cost money?

No. Vee is free and open source — [github.com/navbytes/vee](https://github.com/navbytes/vee).

### How do I install it?

Download the notarized `Vee.app` from [GitHub Releases](https://github.com/navbytes/vee/releases), drag it to `/Applications`, and launch. There is no Homebrew cask yet. See [Getting started](getting-started.md).

### How do I update Vee?

Download the newer `Vee.app` from Releases and replace the copy in `/Applications`. Your plugins folder and settings are separate from the app, so they carry over.

### Where are my plugins stored?

By default in `~/Library/Application Support/Vee/plugins`. You can choose a different folder in the Plugin Manager (for example, an existing SwiftBar folder).

### Where are secrets stored?

In the macOS **Keychain**, namespaced per plugin so one plugin cannot read another's. A preference is treated as a secret when its name contains `token`, `secret`, `password`, `passwd`, `apikey`, or `api_key`; it is masked in the settings form and injected as an environment variable at run time. See [Preferences](preferences.md).

### How does Vee decide how often to run a plugin?

From the plugin's filename: `cpu.5s.sh` runs every 5 seconds, `mail.10m.py` every 10 minutes, and so on (units: `ms`, `s`, `m`, `h`, `d`). A plugin with no interval token runs on demand. You can also schedule with a `<swiftbar.schedule>` cron header. See [Plugin authoring](plugin-authoring.md#filenames-and-refresh-intervals).

### Do I need to compile plugins? What languages can I use?

Any language. A plugin is just an executable that prints to stdout — bash, Python, Ruby, Node, a compiled binary, anything. For TypeScript there is a zero-dependency SDK that runs `.ts` files directly on Node with no build step. See the [SDK docs](sdk.md).

### Can plugins talk back to Vee (refresh, notify)?

Yes — via the `vee://` and `swiftbar://` URL actions (refresh a plugin, refresh all, enable/disable/toggle, notify), or the simpler `refresh=true` line parameter for "re-run me." See [CLI and URL actions](cli-and-urls.md).

### A plugin isn't showing up or is erroring — what do I do?

Check that it is executable (`chmod +x`), in the right folder, and that any interpreter or tool it needs is installed. See [Troubleshooting](troubleshooting.md).
