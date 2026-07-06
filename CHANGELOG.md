# Changelog

All notable changes to Vee are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and Vee follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added (compatibility & UX, batch 2)
- `sfconfig=` now applies SF Symbol `scale` and `weight` (JSON), fixing the
  scale-ignored gap.
- `<swiftbar.hideLastUpdated / hideRunInTerminal / hideDisablePlugin /
  hideSwiftBar>` headers are parsed; a per-plugin "Updated <time>" line is shown
  (suppressed by `hideLastUpdated`).
- `swiftbar://addplugin?src=…` installs a plugin from a URL, and
  `swiftbar://setephemeralplugin` shows transient, file-less menu content.
- `webview=` now opens the URL in a standalone WebView window (never inside the
  menu, preserving the leak-free native menu), sized by `webvieww`/`webviewh`.
- **Debug console** (per plugin, via the gear submenu → "Debug…"): shows the
  last run's exit status, parse diagnostics, and raw stdout/stderr, with a
  "Run again" button — answering "why didn't my plugin work?".
- **Discover: one-click Update** for installed plugins — re-fetches the latest
  catalog source through the same trust gate and overwrites in place.
- **Refresh on wake:** every plugin re-runs when the Mac wakes from sleep, so the
  menu bar is never stale after wake (the top reliability complaint for
  xbar/SwiftBar).
- **Stable menu-bar position:** each plugin's status item now has a persistent
  autosave name, so a position set by ⌘-dragging survives relaunch.
- **Shortcuts & Spotlight (App Intents):** "Refresh All Plugins", "Refresh
  Plugin", and "Enable or Disable Plugin" are exposed as App Intents, so Vee's
  actions can be run from Shortcuts, Spotlight, and automations.

### Changed
- Each plugin's menu now collects Vee's own chrome — the capability summary and
  the Refresh / Settings / About / Reveal / Edit / Quit controls — under a
  single trailing item with a submenu, instead of stacking them around the
  plugin's output.

### Added
- Login-shell `PATH` resolution: at launch Vee recovers the user's interactive
  `PATH` (via `$SHELL -ilc`) and adds the common Homebrew locations, so plugins
  launched from Finder/Dock find Homebrew / pyenv / asdf / nvm binaries the same
  way a Terminal launch would — fixing the most common "works in Terminal, not
  in the launcher" failure.
- Menu-item keyboard shortcuts: the `key=` parameter (e.g. `key=Cmd+R`,
  `key=shift+F2`) is now applied to dropdown items while the menu is open.
- `shortcut=` runs a named macOS Shortcut when a menu item is clicked — a
  lightweight bridge into the Shortcuts ecosystem.
- `dropdown=false` lines are now honored: they are kept out of the dropdown.
- `swiftbar://notify?href=…` notifications are now clickable and open the URL.
- Liquid Glass redesign of the Discover browser, Plugin Manager, install trust
  sheet, and the auto-generated plugin settings form.
- Marketing + documentation website (GitHub Pages, under `docs/`).
- User documentation: getting started, migration, plugin authoring, trust model,
  preferences, SDK, CLI/URL actions, FAQ, and troubleshooting.
- Project hygiene: MIT `LICENSE`, `CONTRIBUTING`, `SECURITY`, issue/PR templates,
  and showcase example plugins under `examples/`.
- Homebrew cask (`Casks/vee.rb`) for `brew install --cask vee` once the
  repository is public.

## [0.1.1] - 2026-07-04

### Added
- Application icon.
- Richer plugin metadata in the Discover browser (title, author, description).

### Fixed
- Dependency and error-state UX in the plugin browser.
- Interpreter detection for non-executable plugins.

## [0.1.0] - 2026-07-04

### Added
- Initial release: a native macOS menu-bar script runner.
- Runs the xbar/SwiftBar plugin protocol unchanged (filename intervals,
  `---`/`--` menus, `|` params, `<xbar.*>`/`<swiftbar.*>` headers, SF Symbols,
  ANSI, Markdown, streaming, cron, `swiftbar://`/`vee://` URL actions).
- Trust-at-install: `<vee.*>` capability declarations with a plain-language
  trust summary and per-plugin badges (advisory, never enforced).
- Declared typed preferences (`<xbar.var>`) rendered as a settings form, with
  secrets stored in the macOS Keychain.
- Discover: a built-in browser over the shared `matryer/xbar-plugins` catalog.
- Zero-dependency TypeScript SDK with a golden-fixture drift guard.
- Developer-ID-signed, notarized distribution outside the Mac App Store.

[Unreleased]: https://github.com/navbytes/vee/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/navbytes/vee/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/navbytes/vee/releases/tag/v0.1.0
