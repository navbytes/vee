# Changelog

All notable changes to Vee are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and Vee follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed
- **`vee new` produced a plugin that could not run.** The scaffolded TypeScript
  plugin imported `./src/vee.ts` and the Python one imported `vee` from its own
  directory, and nothing ever put an SDK at either path — so both failed on
  first run with a module-not-found error. `vee new --out DIR` now writes the
  SDK beside the plugin (and leaves an existing one alone), which is also the
  answer to how a plugin is meant to reach the SDK at all: a Vee plugin is a
  single executable with no build step, so the SDK travels with it.
- **The three SDKs encoded JSON strings three different ways.** Python escaped
  non-ASCII (`✓` became `\u2713`) and Go escaped `<`, `>` and `&` for HTML
  embedding (`R&D` became `R\u0026D`), while JavaScript emitted all of them
  literally. Any widget card with an ampersand in its title already differed
  between Go and the other two. All three now match `JSON.stringify`; the
  `json-demo` fixture carries the characters that expose it.
- **The three plugin SDKs no longer disagree about numbers.** Each SDK's header
  promised byte-identical output; each language's native float formatting
  quietly broke it. Go's `'g'` verb rendered `1000000` as `1e+06` where
  JavaScript and Python rendered `1000000` — so any sparkline, slider, or bar
  carrying a value at or past 1e6 (byte counts, revenue, request totals) went
  out differently from Go. Python and JavaScript in turn disagreed at `1e-7`
  and `1e21`. All three now implement one written-down rule — ECMA-262
  `Number::toString` — verified against 4,011 values including denormals and
  the notation boundaries. No committed fixture exercised a number large enough
  to catch this; `fixtures/edges.txt` now does.
- **A parameter value beginning with a quote no longer loses it.** All three
  SDKs decided whether to quote a value by looking for whitespace, so `"quoted"`
  or `'tis` with no spaces went out bare — and the parser, which decides a value
  is quoted by looking at its first character, read those delimiters as its own
  and stripped them. `tooltip="quoted"` came back as `quoted`. All three now
  quote on a leading `"` or `'`; a quote merely *contained* in a value is still
  safe bare, so existing output is unchanged.
- **The Go SDK under-quoted whitespace.** It tested four characters where the
  TypeScript and Python SDKs test all of JavaScript's `\s`, so a carriage
  return, form feed, vertical tab, or Unicode space went out unquoted. The set
  is now written out by code point in all three, rather than inherited from
  each language's own whitespace class — they differ at the edges.
- **Unknown options in the Python SDK now raise.** They were dropped in
  silence, so `colour="red"` — or `track_color=`, back when the option was
  spelled `trackColor` — emitted nothing at all, with no error. TypeScript
  rejects those at compile time and Go rejects them as unknown struct fields;
  Python now raises `TypeError` and suggests the intended name.
- **Vee can be quit again.** Any plugin with an interval of 10 minutes or more
  (e.g. `prs-and-jira.10m.js`) made the app impossible to close: quitting it —
  from the menu, `⌘Q`, or a `kill` — relaunched it within milliseconds. Long
  intervals were driven by `NSBackgroundActivityScheduler`, which registers a
  **repeating, launch-on-demand XPC activity against Vee's own launchd job**, so
  launchd started Vee back up to service the activity (`immediate reason =
  launch job demand`). Every interval is now driven by the same in-process
  `DispatchSourceTimer` the shorter ones always used, with leeway that still
  lets the system coalesce wake-ups; nothing Vee schedules can relaunch the app.

  The stale registration lives in launchd, not in Vee, so it survives the update
  that stops creating it — on start, each plugin now invalidates the identifiers
  earlier versions used, which unsticks an install that already has one. If you
  hit this before updating, quitting will stick once the new version has run
  with that plugin present.

### Changed
- **The Go SDK's module path is `github.com/navbytes/vee/plugins/go`.** It was
  `vee`, a name that only resolved through a local `replace` directive, so
  `go get` could not reach it. A Go plugin compiles to a binary, so a real
  module path — rather than a vendored file — is how it takes the SDK.
- **`trackcolor=` is deprecated in favour of `progresstrackcolor=`.** It was
  the one control knob not named after its control. The old spelling still
  parses and published plugins keep working; `vee lint` now points at the new
  name, and the SDKs emit only that. Removal is scheduled for the next major
  version.
- **The Python SDK's tuple shorthands are deprecated.** `progress=(72, 100)`
  and `slider=(0, 100, 40)` are spellings only Python accepted — TypeScript
  takes the object form and Go the struct — so a plugin written with them did
  not port. The mapping form works identically in all three; the tuples still
  work behind a `DeprecationWarning`.
- **The Python SDK's options are snake_case.** Menu options were camelCase
  while layout-node options were snake_case, in the same file — so the spelling
  a Python author would reach for first was the one that silently did nothing.
  `trackColor`, `progressW`, `templateImage` and the rest still work and emit a
  `DeprecationWarning`.
- **Invalid layout-node options are rejected.** A `text` node carrying
  `columns`, or a `divider` carrying `spacing`, was accepted by the Python and
  Go SDKs and by the published schema — only TypeScript's types said no. Go now
  refuses at compile time via typed option kinds, Python raises, and
  `widget-card.schema.json` encodes the per-type rule.
- **`check_params.py` checks six surfaces, not three.** The parser, the linter
  and the docs were held in agreement while the SDKs sat outside that triangle,
  which is how fifteen parameters went missing from all three at once. Each SDK
  is now checked separately, so a parameter added to one and forgotten in the
  others fails CI too.
- **Edits to an installed plugin are picked up promptly.** Vee now watches each
  plugin file individually, not just the plugins directory. A vnode source on a
  directory does not fire when an existing file is written, so an in-place edit
  used to be caught only by a 15-second poll; saving a plugin you are editing now
  updates the menu bar in about a debounce. Adding, removing, and renaming
  plugins behave as before, and the periodic tick remains as a backstop.
- **Plugin text now honors `\|`/`\n`/`\\` escapes.** A literal `|`, backslash, or
  newline in menu text or a quoted param value must be escaped as `\|`, `\\`, or
  `\n` — an unescaped `|` now truncates the item and a raw newline splits it into
  two, instead of both being passed through mostly as-is. The TypeScript/Python/Go
  SDKs already escape automatically; hand-written (non-SDK) plugin output that
  prints a literal backslash — e.g. a Windows path `C:\node` — must now write it
  as `C:\\node`.

### Added
- **A typed builder for the structured-JSON format, in all three SDKs.**
  `JSONMenu` mirrors `Menu` method for method — `title`, `dropdown`, `item`,
  `separator`, `submenu`, `print` — so choosing a wire format no longer means
  hand-assembling an object literal. The three emit byte-identical JSON, proven
  by a shared golden fixture. Because the JSON format carries a subset of the
  text protocol's parameters, its option type is distinct: an option JSON
  cannot express is a compile error in TypeScript and Go and a `TypeError` in
  Python, rather than a key dropped on the way out.
- **`vee sdk <ts|py> [--out DIR]`** writes the plugin SDK into a directory, so a
  plugin copied out of the examples can import it as a sibling file.
- **The same sparkline knobs in the JSON output format.** `sparklineWidth`,
  `sparklineHeight`, and `sparklineColor` join `progressWidth`/`progressHeight`
  there, and `progressTrackColor` replaces `trackColor` (still accepted). The
  JSON format documents its rich params as mapping onto "exactly the same
  controls" as the text protocol, so it gains every control knob the text
  protocol does.
- **`sparklinew=`, `sparklineh=`, `sparklinecolor=`.** The sparkline was the
  only inline accessory with no size or colour knob — `progress=` had
  `progressw`/`progressh`/`trackcolor` and a chart had
  `chartw`/`charth`/`chartcolors` — so it now takes the same vocabulary,
  `sparklinew=full` included.
- **Fifteen parameters the SDKs could not emit.** `accessory`, `header`,
  `ansi`, `emojize`, `trim`, `dropdown`, `image`, `templateimage`, `sfcolor`,
  `sfsize`, `sfconfig`, `shortcut`, `webview`, `webvieww`, and `webviewh` were
  recognised by the parser, listed by the linter, and documented for authors —
  and no SDK had any way to write them. `accessory` was the sharpest omission:
  it places `progress=`, `sparkline=`, and every chart shape, all of which the
  SDKs could already emit. The format's `progress=value,max` form is reachable
  from the SDKs now too.
- **`vee.Stat`, `vee.Gauge`, `vee.Trend`, `vee.List`, `vee.Board`.** The Go SDK
  had none of the five widget template constructors TypeScript and Python both
  shipped; a Go author set `Template:` by hand.
- **`vee dev` — a save-driven authoring loop.** `vee dev <path>` watches one file
  and re-runs it on **every save**, repainting the parsed menu tree, the run
  status, and any lint findings. Where `vee show` re-runs on the plugin's own
  cadence — so an edit to a 5-minute plugin appears five minutes later — this
  re-runs when you hit save. A broken save repaints with the exit code and stderr
  and keeps watching rather than exiting.

  `--text` treats the file as plugin *output* and never executes it, so a menu's
  shape can be designed as plain text with no shebang, no execute bit, and no
  code running on save. `--push` additionally renders each save as a real
  menu-bar status item with no file written to the plugins folder, so the
  terminal shows structure while the menu bar shows Vee's true render; it is
  opt-in, and the preview is removed on exit. Executable (`shell=`/`bash=`) rows
  appear in a pushed preview but do not fire — ephemeral content is defanged
  because any web page can open a `vee://` URL — and the loop says so rather than
  letting a row silently do nothing.
- **`vee lint --format compact`** emits `path:line:col: severity: message`, the
  shape VS Code, vim, and emacs already parse, so findings become inline
  diagnostics with no Vee-specific editor extension. Because lint runs over a
  plugin's *output*, an executed script's findings are attributed to `<stdout>`
  rather than to the script — a loop emitting many rows from one `echo` has no
  recoverable line mapping, and marking an innocent source line would be worse
  than marking none. Lint the protocol text with `--text` for diagnostics that
  land exactly. `vee lint <path>` with no flags is unchanged.
- **Detached plugin windows — leave a plugin open on the desktop.** *Open in
  Window*, in a plugin's own dropdown beside Refresh and Debug, opens that
  plugin's whole menu surface as a resizable window you can move to another
  display and leave open; the search panel gains a *keep open* button that
  promotes the panel already in front of you. The window is not a snapshot — it
  updates on the plugin's own refresh interval, so a one-second `sparkline=`
  moves once a second, which a Notification Center widget cannot do (WidgetKit
  floors refresh at five minutes). It works for any plugin with no `<vee.*>`
  declaration required.

  One window per plugin, as many plugins at once as you like; reopening a plugin
  focuses its existing window rather than stacking a second. Each window has a
  pin control in its title bar: pinned (the default) floats above other apps,
  follows you across Spaces, and stays visible over a full-screen app; unpinned
  behaves like an ordinary window. Vee remembers the choice per plugin for the
  session. A new **Detached Windows** submenu in Vee's own menu lists every open
  window and brings one to the front — Vee has no Dock icon, so that submenu and
  the plugin's hotkey are the reliable ways back to a window you have unpinned
  and covered up. When a plugin is disabled, removed, or starts erroring, its
  window keeps the last output on screen and says it is stale rather than
  quietly freezing on a number that looks current. Windows are per-session and
  do not reopen after quitting.

  This is the existing search panel with a second presentation rather than a new
  surface: the same view, the same rows, the same dispatcher, so the window
  carries the panel's search field and neither can drift from the other on what
  a row means. The rows themselves gain the rich family the panel omitted —
  `progress=` gauges, `sparkline=`, `pie=`/`donut=`/`stackedbar=`, and live
  `toggle=`/`slider=` controls that run the plugin's command from the row.
  Colors, gauge dimensions, and chart geometry come from the same sources the
  menu and the popovers read, so the surfaces agree by construction. Two things
  are deliberately not reproduced, both meaningful only inside an open menu: an
  `⌥` alternate is shown as an ordinary row (visible and clickable — more than
  the dropdown offers without the modifier held), and per-row `key=` equivalents
  are not bound.
- **A plugin's global hotkey can open its window.** `<vee.shortcut>` keeps its
  single declaration and single binding; the plugin's Settings now chooses what
  it opens — the search panel (the default, so every plugin that already
  declares one is unaffected) or the window. Nothing is given up either way,
  since the window carries the search field too. With *Window* selected,
  pressing the hotkey when the window is already open brings it back to the
  front. Rebinding, turning it off, the in-use/invalid status, and the trust
  sheet's disclosure all work exactly as before.
- **Share charts — `pie=`, `donut=`, and `stackedbar=`.** A new family of
  Vee-native line params for showing how a total divides up, alongside
  `sparkline=`'s value-over-time. All three take the same data — one series of
  non-negative numbers read as shares of a whole (`pie=45,30,25`) — so switching
  shapes changes one word. The chart draws **inline in the menu row** (a real
  pie/donut/capsule bar in a custom AppKit view, in the same accessory slot
  `progress=` and `sparkline=` use, honoring `accessory=leading`); clicking the
  row opens a Liquid Glass Swift Charts popover with the chart at full size and a
  legend naming every segment with its percentage. `chartlabels=` names the
  segments and `chartcolors=` recolors them — both positional, so a blank or
  entry that is blank, malformed, or names a color Vee doesn't know keeps that
  segment's own default rather than sliding the next color onto it. Segments otherwise take a built-in eight-slot categorical
  palette, assigned by position and never cycled, with light and dark steps
  selected per surface and checked for color-blind separation. The parser refuses
  to draw a series it can't read as shares (non-finite, negative, or all-zero,
  each with a diagnostic), and folds a series longer than eight segments into a
  neutral "Other" tail rather than truncating it, so the shares still add up to
  the plugin's own total. Available in the structured-JSON format as a `chart`
  object, in all three SDKs as one typed `chart`/`Chart` builder, and in
  `vee show` as a segmented block bar (`vee render` names the shape).
  `chartw=`/`charth=` size the inline chart in points (defaults: a 24pt circle,
  a 110x12 bar; clamped to 8-200), and `chartw=full` stretches it to the width
  the row actually has — a row with empty text before the `|` then gives the
  chart the whole row. VoiceOver reads every segment and its share, on both
  the row and the popover.
- **Search panel shows menu structure.** When idle (before typing), the search panel
  now mirrors the dropdown's structure — section headers (`header=true`), separators
  (`---`), and non-actionable rows (plain sub-text and `disabled=true` items) appear
  dimmed and non-selectable, just like the native menu. Section titles join the
  breadcrumb context and are searchable, so typing a section's name surfaces its rows.
  Nested submenus' headers/separators don't render as rows (their structure is carried
  by breadcrumbs like `Tools › Nested`); header submenus never surface items. While
  typing, results flatten into a ranked list and dimmed info rows match too but stay
  non-activatable — the same filter you'd use to find rows also helps you browse
  menu structure when you're just exploring.
- **`vee show` — a live terminal view of a plugin's dropdown.** A new authoring
  subcommand renders what a plugin's menu-bar dropdown would look like, natively
  in the terminal, and live-refreshes it on the plugin's own filename cadence
  (`r` to refresh now, `q`/`Ctrl-C` to quit). `<plugin>` is a path or the name of
  an installed plugin. Rich params render the way a terminal can — `color=`/ANSI
  as real SGR, `progress=` as a Unicode block gauge, `sparkline=` as a block
  sparkline, `toggle=`/`slider=` as inline state — and things a terminal can't
  draw (SF Symbols, base64 images) are shown by name rather than dropped. A status
  line reports cadence + last exit code; parse diagnostics and stderr surface
  below, like `vee render`. `--once` prints a single frame (also the piped/non-TTY
  behavior); `--no-color`/`NO_COLOR` disable color; `--dir` sets the folder a
  plugin *name* resolves against. Reuses the existing AppKit-free cores
  (`VeeRuntime`/`VeePluginFormat`); the pure renderer (`TerminalRenderer`) and
  name/path resolver (`PluginResolver`) are unit-tested, with only the raw-mode
  live loop (`LiveView`) touching the real terminal.
- **Compact menu-bar mode.** An opt-in General setting collapses every plugin
  into rows of a single "Vee" status item (issue #45), solving menu-bar crowding
  for users with many plugins. Each plugin's submenu and menu behavior stay
  unchanged; General settings toggle, default off.
- **Inline sparkline rendering.** `sparkline=` rows now render a sparkline
  **inline in the menu row** itself (alongside text, like `progress=`), with the
  click-to-popover behavior retained. Clicking opens a richer native Liquid Glass
  Swift Charts visualization.
- **Accessory placement control.** `accessory=leading` / `accessory=trailing`
  places a `progress=` or `sparkline=` accessory at either edge of a row (default
  trailing, today's rendering).
- **Native section headers.** `header=true` renders a line as a real, non-interactive
  macOS section header (`NSMenuItem.sectionHeader`) instead of a `disabled=true` line
  dressed up to look like one — rendering is native, no click handling.
- **Catalog update nudge.** A coalesced notification surfaces "N plugin updates
  available" (one notification per version, de-duped), opening Discover so users
  can install. Never auto-installs. Checks run at app launch against the catalog
  snapshot saved by the last Discover visit — no network call at launch — and
  after every Discover refresh (suppressed while the Vee window is already in
  front). Updates are matched by install origin, so an entry from one store can
  never masquerade as an update for a plugin installed from another.
- **Per-plugin execution timeout override.** `<vee.timeout>ms/s/m/h/d` header
  sets a per-plugin timeout (or a plain number of seconds; decimals allowed).
  Clamped to 1s–1h (default 30s). Debug console surfaces 8MB output truncation
  and 1MB streaming line caps.
- **Cross-plugin "Search All Plugins" panel.** A **Search All Plugins…** item
  in Vee's main menu now opens the same Spotlight-style search panel merged
  across *every enabled plugin's* current menu at once, not just one plugin's
  — each row breadcrumb-prefixed with its plugin's name (itself
  fuzzy-searchable), still firing through that plugin's own action handler and
  never a shared one. An opt-in global hotkey (General settings, no default
  combination, mirroring the per-plugin hotkey pattern) opens it from anywhere.

### Changed
- **Discover loads with skeleton cards.** While the catalog fetches, Discover now
  shows placeholder cards in the real grid instead of a centered spinner, so the
  pane settles into place rather than flipping from spinner to full grid.
- **Install trust sheet reads as a table.** The "What this plugin can do"
  permissions and the "Features it adds" rows are now grouped into an inset card
  with hairline row dividers, so each list scans as one block instead of floating
  rows.
- **Installed section polish (UX tier 2).** The sidebar's **Installed** row now
  carries a live plugin count as a native badge; the list shows placeholder
  skeleton rows while it loads instead of a lone centered spinner; and the row
  badges follow the tier-1 doctrine — schedule, surface, and hotkey are muted
  `MetaChip`s while trust and error stay filled `TrustChip`s, with state leading
  and metadata trailing.
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
- **Context7 indexing.** A `context7.json` at the repo root scopes
  [Context7](https://context7.com) to the guides in `docs/_content` (plus the
  always-included root docs) and ships a set of `rules` so AI coding assistants
  answer with Vee's actual conventions (filename intervals, `<vee.*>` trust tags,
  `<xbar.var>` config, the typed SDKs, `<vee.surface>` widgets).
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
