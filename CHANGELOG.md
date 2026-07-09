# Changelog

All notable changes to Vee are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and Vee follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- **Homebrew moves to a dedicated tap.** Install is now `brew tap navbytes/tap`
  (the [`navbytes/homebrew-tap`](https://github.com/navbytes/homebrew-tap) repo)
  instead of tapping the app repo directly. The release workflow keeps the tap in
  sync automatically on every release via
  [`scripts/update-homebrew-cask.sh`](scripts/update-homebrew-cask.sh) — it
  publishes/bumps the cask's `version` + `sha256` from the built asset (gated on a
  `HOMEBREW_TAP_TOKEN` secret; skipped when unset). The old in-repo `Casks/`
  self-tap, which had to be bumped by hand and had drifted, is retired.
- **Calmer, more native visual language.** Introduced a visual-foundation token
  set in `DesignKit` (a neutral system-surface ladder + hairlines, one brand
  accent, an 8pt spacing grid, semantic type roles) and split badges into two
  weights — filled `TrustChip` for state that matters (trust, error) vs. a muted
  `MetaChip` for descriptive metadata (freshness, store). Discover cards now show
  one ranked badge row instead of a vertical ladder of same-weight pills, with
  freshness demoted to muted text and a hairline-at-rest card surface.

### Added
- **A plugin's Settings and Debug now open in-pane.** Selecting an installed
  plugin in the consolidated window's **Installed** section shows its
  **Settings** and **Debug** as tabs in the detail pane (with a back button)
  instead of opening separate per-plugin windows. The debug console updates live,
  sharing the same model the pop-out window uses. The menu-bar status-item menus
  and the notification "Open Log" action still open the standalone per-plugin
  windows.
- **One consolidated Vee window.** The Plugin Manager, Discover, and Preferences
  windows are now a single sidebar window — **Installed**, **Discover**,
  **Variables**, **Stores**, and **General** as sections. ⌘M opens it on
  Installed, ⌘D on Discover, and ⌘, focuses General, so the whole "manage my
  plugins + settings" workflow lives in one place (the folder/launch-at-login
  controls are no longer duplicated across two windows). The Discover catalog
  browser is now **embedded directly** in the window — its category/store filter
  moved from a nested sidebar into toolbar menus so it renders as a single
  column (no nested split view), and the retained catalog still opens instantly
  on reopen. See `docs/design/ui-consolidation.md`.
- **Widget-only plugins are flagged in Discover and the Manager.** A plugin
  with `<vee.surface>widget</vee.surface>` (no menu-bar item) now shows a
  "Widget-only" badge in the Plugin Manager, and — when a custom store declares
  a plugin's `surface` in its `vee-catalog.json` — in the Discover grid before
  install, so a plugin with no menu-bar presence isn't a mystery.
- **Composable widget layout tree.** A widget card can now carry a `layout` —
  a bounded tree of native primitives (`vstack`/`hstack`/`zstack`/`grid`,
  `text`/`image`/`gauge`/`sparkline`/`spacer`/`divider`) with per-element style
  — as an escape hatch alongside the five preset templates, for widgets the
  presets can't express (two columns, a date rail, activity rings, KPI grids).
  It's *describe, don't draw*: no WebView, no freeform canvas. The tree is
  sanitized and capped app-side on parse (depth ≤ 8, ≤ 64 nodes, clamped
  numerics) so the sandboxed extension only renders. The TypeScript, Python,
  and Go SDKs gain namespaced `Node.*` builders, with a `widget-layout` golden
  fixture verified byte-identical across all three.

### Changed
- **Discover opens instantly on reopen.** The catalog is now retained across
  window opens instead of being re-fetched from the network every time, so
  reopening Discover shows the already-loaded plugins immediately. It rebuilds
  only when the store set or plugins folder changes; the toolbar Refresh button
  still forces a fresh fetch. First step of a broader window-consolidation and
  loading-UX effort (see `docs/design/ui-consolidation.md`).
- **The Plugin Manager opens instantly.** Building each row read and parsed
  every plugin file synchronously on the main thread when the window opened;
  that work now runs off the main thread and the window shows immediately with
  a brief loader while the rows populate.

### Fixed
- **Search panel swallowed row actions meant for the previous app.** Presenting
  the `⌘⇧`-style search panel force-activates Vee (needed so its search field
  can become key), but nothing restored the app you were in before opening it.
  A row's action — e.g. a clipboard plugin simulating `⌘V` — fired while Vee
  was still frontmost, so it never reached the app you meant to paste into.
  The panel now captures the frontmost app before activating itself and
  restores it on every dismissal path (row pick, Esc, outside-click).
- **Crash on `length=-1`.** A negative `length=` reached `String.prefix(_:)`,
  which traps — a plugin printing `foo|length=-1` crashed the whole menu-bar app
  on every render. `length` is now clamped to `>= 0` at parse time.
- **Misidentified missing command.** The "…" not-found hint parsed the wrong
  colon-field of real bash output and named the script path instead of the tool;
  it now anchors on the marker.
- **Tab-separated params** were swallowed into the preceding value; a tab now
  separates params like a space.
- **Non-SGR ANSI escapes** (cursor move / erase, e.g. `ESC[K`) ate the text up to
  the next `m`; they are now stripped per the CSI grammar without touching style.
- **In-place plugin edits took effect only after a toggle/relaunch.** The reload
  now keys on each plugin file's modification time, so editing a header (schedule,
  hotkey, `runInBash`, trust) applies immediately.
- **Process drain could hang/leak** when a grandchild kept stdout open after the
  plugin exited; a drain-grace now force-completes the run and releases the reads.
- **Scheduling drift and a runaway timer are fixed.** Cron used the monotonic
  clock, so a fire due during sleep landed hours late on wake instead of
  firing promptly — it's now wall-clock. A `0s`/`0ms` interval filename (e.g.
  `cpu.0s.sh`) armed a near-zero-period repeating timer that pegged a CPU
  core; it's now rejected at parse (falling back to manual refresh) and
  floored as a backstop.
- **Some in-place plugin edits and a replaced plugins folder went
  undetected.** The directory watcher only fired on entry add/remove/rename,
  so an edit that didn't touch the directory listing (as some editors'
  atomic-save does) could go unnoticed; a periodic poll now catches it too.
  If the plugins folder itself was deleted and recreated, the watcher went
  silently inert until relaunch — it now detects and reopens automatically.
- **Editor backup and autosave files no longer run as plugins.**
  `plugin.sh~`, `#plugin.sh#`, and files ending `.bak`/`.orig`/`.tmp`/`.swp`/
  `.swo`/`.rej` are now skipped, so a stale (possibly credential-bearing)
  copy can't execute alongside the real plugin.
- **Windows-line-ending output parses correctly.** A `---`/`--`/`~~~`
  separator followed by `\r` used to be missed entirely, rendering the whole
  output as title lines; CRLF is now tolerated at the line-split boundary in
  the parser, the streaming path, and `vee lint`. A bare `ESC[m` (the reset
  `git`/`grep --color` emit) now actually resets styling instead of bleeding
  color to the end of the line.
- **Refreshing a streaming plugin no longer clobbers it with a spurious
  timeout error.** "Refresh All", wake, Shortcuts, and the menu's own Refresh
  used to spawn a duplicate one-shot run of a streaming plugin — which never
  exits — so it always timed out and replaced the live stream with an error;
  a refresh now restarts the stream instead.
- **Replacing an ephemeral menu (`setephemeralplugin`) now renews its
  expiry.** Updating the same ephemeral item used to leave the old deadline
  running, so it could vanish earlier than the new `exitafter` promised, or
  (with no `exitafter` at all) still expire on the old schedule.
- **`href=` items now honor `refresh=true`, and `progress=` rows keep their
  submenu and action.** Both previously matched xbar/SwiftBar's behavior only
  partially — a `href` click with `refresh=true` didn't trigger a refresh,
  and a `progress=` gauge with a submenu or its own action silently lost it
  in the native menu.
- **Several Discover browser bugs are fixed.** Reopening the browser used to
  keep showing the model it was built with — installs could even target the
  wrong store or directory; it now reflects a newly added store or changed
  plugins folder, and gained a Refresh toolbar button (⌘R) to re-fetch the
  catalog on demand. The freshness badge, which read a differently-keyed
  cache than the one the fetch wrote to, renders again too.
- **The per-plugin debug console works again after a plugin reload.** A
  closed debug window's tracking entry was never cleared, so a reload could
  leave "Run again" bound to a deallocated coordinator.
- **A typed hotkey combo is now saved when clicking Save**, not only when
  committed with Return.
- **Plugins are now reliably killed instead of leaking.** A plugin that
  timed out while it had backgrounded a helper (`sleep 900 &`, a stray
  `curl`) used to leave that helper running forever, since only the direct
  child was ever signaled — every plugin now runs as the leader of its own
  process group, so a timeout's SIGTERM/SIGKILL reaches everything it
  spawned. Stopping a streaming plugin now escalates to SIGKILL and
  force-closes its pipe if the script ignores SIGTERM (or a grandchild is
  still holding the pipe open), instead of leaking a thread and both fds on
  every reload.

### Security
- **`swiftbar://addplugin` now requires confirmation.** The deep link previously
  fetched, wrote executable, and auto-ran a plugin with no gate — unattended code
  execution any web page could trigger. It now shows the plugin's capability
  footprint and requires an explicit Install click, streams the download with a
  1 MB cap, rejects a non-2xx status, and fails closed on an unusable filename.
- **`swiftbar://setephemeralplugin`** content injected via URL now has its
  `shell=`/`bash=` actions stripped, removing a one-click arbitrary-exec vector.
- The widget snapshot file is written owner-only (`0600`).
- **A remotely-triggerable crash via `exitafter` is fixed.**
  `swiftbar://setephemeralplugin?...&exitafter=1e40` (or `inf`) — a link any
  web page can open — reached a `Double`-to-`UInt64` conversion that traps on
  overflow, crashing the whole app. The value is now rejected when
  non-finite and clamped to a 24-hour ceiling.
- **The install trust sheet now names the actual store a plugin comes
  from**, instead of always claiming `matryer/xbar-plugins` — false
  provenance on a security-relevant surface for enterprise and
  user-configured stores.

### Changed
- Widget snapshot timestamp-only writes are throttled (content changes still
  write immediately), and the Discover catalog fetch is buffered instead of read
  byte-by-byte — less disk/CPU churn. `refreshAll` staggers plugin spawns so
  wake/launch doesn't start every subprocess at once.
- **Identical plugin output no longer rebuilds the menu.** When a refresh
  produces byte-for-byte the same output as last time — the common case —
  Vee skips rebuilding the `NSMenu` and just updates the "Updated `<time>`"
  stamp in place; resolved SF Symbol/image renders are also cached, so
  repeated refreshes don't redecode them.

### Added
- **Widgets rebuilt into real dashboard tiles.** The WidgetKit widget is no
  longer a monospaced copy of the menu bar. It now (a) lets each instance
  **choose which plugins to show** (an `AppIntentConfiguration` picker; empty =
  all), (b) renders a **single-plugin "hero" tile** at the small size — SF
  Symbol in its color, the big value, and the plugin's `progress=` gauge or
  `sparkline=` trend drawn natively — and enriched rows at medium/large, and (c)
  shows **honest freshness** ("2 min ago"). To feed this, the snapshot the app
  publishes gained the presentation it already computed (color, SF Symbol,
  progress fraction, sparkline series, error flag, refresh interval); the format
  is versioned (v2) and still decodes a v1 snapshot. A second widget, **Vee
  Health**, surfaces the one thing the menu bar can't: an aggregate roll-up
  ("6 OK · 1 failing") with the failing plugins called out.
- **Widget surface contract:** a plugin can now feed its widget tile *data*
  instead of a scrape of its menu-bar line. `<vee.surface>both</vee.surface>`
  runs the plugin a second time with `VEE_TARGET=widget` on the plugin's
  filename interval (small 10s floor; the always-running app pushes widget
  reloads on data change, so no 5-minute cap), and reads one JSON "card"
  object from stdout — `stat`/`gauge`/`trend`/`list`/`board`, each a native
  SwiftUI template rendered per widget family. `<vee.surface>widget</vee.surface>`
  makes a plugin **widget-only**: no status item, no menu, feeding just the
  widget. A card's `refresh`/`shortcut` action buttons run through a new
  per-plugin request channel (the widget extension writes a small request
  file and signals the app, generalizing the existing refresh-all control);
  `href` actions open directly, scheme-filtered like menu `href=`. Every
  plugin still has a widget representation with zero changes — the scrape
  (now snapshot v3) is the default and the fallback when a `both`/`widget`
  plugin doesn't emit a card. The TypeScript, Python, and Go SDKs all gained
  `WidgetCard`/`Stat`/`Gauge`/`Trend`/`List`/`Board` builders, with a shared
  golden fixture round-tripped through the Swift parser.
- **Searchable filter panel** (opt-in via `<vee.filter>true</vee.filter>`): a
  plugin's menu gains a **Search…** row (⌘F) that opens a Spotlight-like panel
  filtering every item — including those nested in submenus — flattened into a
  ranked list with breadcrumbs. Fuzzy matching (`gh` → `GitHub`), multi-token
  AND, ↑/↓ + Return to activate, Esc to close. Activating a row dispatches
  through the plugin's existing action, so href / shell / shortcut / refresh and
  the toggle/slider/sparkline popovers all work unchanged. The native menu, its
  trust row, and the controls footer are untouched — the panel is an additional
  surface, not a replacement. Also available from the CLI: `vee search <plugin>
  [query…]`.
- **Global search hotkey** (opt-in via `<vee.shortcut>cmd+shift+k</vee.shortcut>`):
  a plugin can bind a system-wide hotkey that opens its search panel from
  anywhere, without opening the menu first. Registered with Carbon
  `RegisterEventHotKey` — no Accessibility permission and no third-party
  dependency. Omit the tag for no hotkey.
- The structured-JSON output format now supports the rich inline controls —
  `sparkline`, `toggle`, `slider`, and `progress` (plus `trackColor` /
  `progressWidth` / `progressHeight`) — as typed item fields, mapping to the same
  controls as the text protocol.

### Security
- **URL scheme validation.** Plugin-supplied `href=` / `webview=`, the
  `<xbar.abouturl>` header, the `notify?href=` action, and
  `swiftbar://addplugin?src=` are now scheme-filtered: `href`/about-URL block
  `file`/`javascript`/`data`/`vbscript`/`blob` (custom app deep links still
  work), while `webview` and remote fetches are restricted to `http`/`https` —
  so a menu click, the About dialog, or a notification can't open a local file,
  load local content into an in-app WebView, or install a plugin read from
  `file://`.
- **Catalog network hardening.** Discover's fetches reject a non-2xx HTTP status
  (an error body is no longer parsed as catalog data) and stream with a per-
  endpoint byte cap, so a compromised/redirected upstream can't exhaust memory.
- **Path traversal in plugin install fixed.** `swiftbar://addplugin?src=…`
  derived the on-disk filename from the URL's `lastPathComponent`, which
  percent-decodes — so a crafted `src` (`…/..%2f..%2fevil.sh`) could write an
  executable outside the plugins directory. Filenames are now validated as a
  single safe path component and the resolved path is confined to the plugins
  folder.
- **Run-in-Terminal injection fixed.** Untrusted plugin values (`bash=`,
  `paramN=`) are now POSIX single-quote escaped and the AppleScript string is
  escaped, so a menu item can no longer inject shell or AppleScript on click.

### Added
- **`vee` command-line tool** — `vee render <plugin>` prints the parsed menu
  tree + diagnostics (text or JSON plugins), `vee lint <plugin>` flags unknown
  params / bare `|` in titles / unquoted values, and `vee new` scaffolds a
  plugin with `<xbar.*>`/`<vee.*>` headers. Running `vee` with no subcommand
  still launches the menu-bar app.
- **Typed rich-param SDK builders** for `sparkline`/`toggle`/`slider`/`progress`
  (+ `trackColor`/`progressW`/`progressH`) across the TypeScript, Python, and Go
  SDKs, with quoting/escaping handled internally and a golden fixture shared
  byte-for-byte across all three and round-tripped through the Swift parser.
- **`ARCHITECTURE.md`** — a contributor guide to the module graph, the leak-free
  execution pipeline, the parser, the trust model, and the widget channel.
- **Homebrew install** surfaced across the README and docs
  (`brew install --cask vee`).

### Fixed
- Non-finite numeric params (`progress=nan`, `size=inf`, …) are rejected at the
  parser instead of producing NaN bar geometry / `NSFont` sizes.
- Subprocess output buffers are now bounded (stdout/stderr capture, the
  streaming partial line, and the `~~~` accumulator), preserving the
  bounded-memory guarantee against a plugin that spews output without limit.
- The JSON output parser caps menu nesting depth so deeply-nested `submenu`/
  `alternate` chains can't overflow the stack.
- ANSI color runs now map through UTF-16 offsets, so text mixing ANSI colors
  with emoji / non-BMP characters is colored correctly instead of shifted.
- Per-plugin settings windows no longer leak: closing one via the title-bar
  button (not just the Done button) now clears its tracking entry.

### Changed
- The SwiftLint tree is clean and CI now runs `swiftlint --strict` as a hard gate.

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
