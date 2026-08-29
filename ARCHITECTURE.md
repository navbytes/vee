# Vee architecture

This document explains how Vee is put together, for people who want to
contribute. For *using* Vee or *writing plugins*, see the
[docs site](https://navbytes.github.io/vee/); this is about the internals.

Vee is a native macOS menu-bar script runner: it discovers executable
"plugins", runs them on a schedule, parses their stdout as the xbar/SwiftBar
text protocol, and renders the result as `NSStatusItem` titles and `NSMenu`
dropdowns. It ships with **zero third-party dependencies** — everything below is
the Swift standard library, Foundation, AppKit/SwiftUI, and system frameworks.

## Design goals (why the code looks the way it does)

1. **Leak-free over long uptime.** The category's #1 complaint about xbar and
   SwiftBar is that plugins silently stop refreshing after sleep/wake and that
   memory/CPU creep over hours. Vee's runtime is built to make those failure
   modes structurally hard — see [The execution pipeline](#the-execution-pipeline).
2. **Native, no embedded web runtime in the menu.** The menu bar is pure AppKit
   (`NSMenu`). Rich UIs (charts, toggles, sliders) are delivered by native
   popovers and WidgetKit, never by embedding a WebView or a cross-platform UI
   framework in the menu.
3. **Testable core, thin shell.** All logic lives in library targets covered by
   `swift test`. The `vee` executable and the AppKit view layer are kept as thin
   as possible so the interesting behavior is exercised without a GUI.
4. **Transparency, not a sandbox.** Plugins are arbitrary un-sandboxed
   executables (the model requires it). Vee differentiates with an *advisory*
   trust layer that surfaces what a plugin can do — never by enforcing an OS
   sandbox.

## Module graph

Vee is a modular SwiftPM package (`Package.swift`). Dependencies point downward
only; there are no cycles.

| Module            | Responsibility |
| ----------------- | -------------- |
| `VeeCore`         | Shared value types with no platform dependencies: `RefreshInterval`, `PluginFilename`, `PluginID`, `VeeClock`, `VeeError`, `VeeLog`. |
| `VeePluginFormat` | The pure parser. Turns plugin stdout into a `ParsedOutput` (title lines + a menu-node tree) plus `ParseDiagnostic`s. Handles the `---`/`--` menu structure, `\|`-delimited params, `<xbar.*>`/`<swiftbar.*>`/`<vee.*>` headers, ANSI, emoji `:shortcodes:`, colors, SF Symbols, and the alternative structured-JSON output. Never throws — malformed input degrades to best-effort output + diagnostics. |
| `VeeRuntime`      | Plugin discovery, **leak-free execution**, scheduling, environment building, `PATH` resolution, and `~~~` streaming. The heart of the reliability story. |
| `VeeMenu`         | Emits an `NSMenu` from a resolved `MenuTree`, deciding nothing itself: color/ANSI attribution, SF Symbol images, key equivalents, actions, and the custom in-row `progress=` view. |
| `VeeSearch`       | Pure, AppKit-free matching. `MenuTreeFilter` narrows a `MenuTree` to matches plus their ancestors, preserving structure and order — what the transient `<vee.filter>` panel and the detached window use; `MenuTreeDisplay` projects the result into the lines they draw. `MenuFlattener`/`MenuSearch` keep the older flat, breadcrumb-annotated, fuzzy-**ranked** projection, now used only by `vee search`. |
| `VeePreferences`  | The `<xbar.var>` preferences sidecar and the Keychain-backed `SecretStore`; the cross-plugin `VariableAggregator` behind the Variables editor. |
| `VeeTrust`        | The advisory trust layer: `SourceScan` statically scans plugin source for capability keywords and diffs detected-vs-declared; `TrustDiff` compares footprints across an update. |
| `VeeCatalog`      | The Discover browser over `matryer/xbar-plugins`: catalog fetch/parse, freshness classification, install (with path-traversal-safe filenames), and `PluginProvenance` (source URL + content hash so later tampering is detectable). |
| `VeeUI`           | SwiftUI windows and views: Preferences, Plugin Manager, Discover, plugin settings forms, the debug console, the Liquid Glass sparkline/control popovers, and the compact row graphics a detached window draws inline (`MenuRowAccessory`). |
| `VeeWidgetShared` | A tiny Foundation-only model + store shared with the WidgetKit / Control Center extension. See [The widget cross-process channel](#the-widget-cross-process-channel). |
| `VeeApp`          | The AppKit shell: `AppController`, `PluginCoordinator`, status-item management, App Intents, the URL/action routers, and notifications. Kept as a library so it is unit-testable. |
| `VeeCLI`          | The zero-install authoring CLI: `render`, `lint`, `new`, `search`, `show`, and `dev`. AppKit-free and kept as a library so the CLI surface is unit-testable without a GUI. |
| `vee`             | The executable: a thin entry point that either boots the app or dispatches the `render`/`lint`/`new`/`search`/`show`/`dev` authoring subcommands (`VeeCLI`). |

Dependency edges (downward):

```
VeeCore ─┬─► VeePluginFormat ─┬─► VeeRuntime ─► VeeApp ─► vee
         │                    ├─► VeeMenu ──────► VeeApp
         │                    ├─► VeeSearch ────► VeeApp   (also VeeCLI)
         │                    └─► VeePreferences ─► VeeUI ─► VeeApp
         ├─► VeeTrust ──────────────────────────► VeeUI
         └─► VeeCatalog ────────────────────────► VeeUI
VeeWidgetShared ─┬────────────────────────────► VeeApp   (also linked by the widget extension)
                 └────────────────────────────► VeePluginFormat
```

`VeeCatalog` and `VeeWidgetShared` are otherwise dependency-light on purpose —
`VeeWidgetShared` links almost nothing so the sandboxed widget extension stays
tiny.

## The execution pipeline

A single plugin refresh flows through the runtime like this:

```
RefreshTimer (per-plugin interval) ──fires──▶ PluginRuntime.refresh(pluginPath:…)
                                                    │
                                                    ▼
                                          PluginExecutor.run(…)        build launch command
                                                    │                   (shebang / bash), merge
                                                    ▼                   environment + PATH
                                          SystemProcessRunner.run(…)   spawn, drain, time out
                                                    │
                                                    ▼
                                          ProcessOutcome (stdout/stderr/exit/timedOut)
                                                    │
                                                    ▼
                                          OutputParser.parseAuto(stdout)  JSON-or-text → ParsedOutput
                                                    │
                                                    ▼
                                          MenuBuilder → NSMenu / NSStatusItem title
```

`RefreshScheduler` drives every interval with a high-resolution
`DispatchSourceTimer` (`RefreshTimer`), sized with a leeway (~15% of the
interval) that lets the system coalesce wake-ups. `WakeMonitor` re-runs
everything on wake from sleep.

Long intervals (≥10 min) used to go to `NSBackgroundActivityScheduler` instead,
for OS-level energy batching. That is **deliberately no longer used anywhere**:
it registers a repeating, *launch-on-demand* XPC activity against Vee's own
launchd job, so launchd relaunched Vee within moments of the user quitting it
and the app could not be closed at all. The registration lives in launchd rather
than in the app, so it also survives the update that stops creating it.
`VeeRuntime/LegacyBackgroundActivity.swift` invalidates the old identifiers, and
`AppController` sweeps them **once at launch** over every plugin ID Vee has ever
loaded (`AppPreferences.seenPluginIDs`) — not just the ones installed now.

That distinction is the whole fix. An identifier can only be built from the
plugin ID that registered it, so clearing per plugin at start leaves an activity
registered by a since-deleted plugin permanently unnameable, and the install
stays un-quittable forever. An affected machine was found in exactly that state:
its remaining plugins refreshed at 30s and 90s, so nothing loaded could clear
anything. The sweep therefore runs unconditionally, with no "already migrated"
flag — a stale registration can return via a downgrade, a restored backup, or
synced preferences — and it reports what it *attempted*, since
`NSBackgroundActivityScheduler` cannot say whether an identifier was ever
registered. Energy
batching is a poor trade for an app the user cannot quit, and it bought little
for a resident menu-bar app that is running anyway.

### Why it stays leak-free

The crown-jewel file is `VeeRuntime/SystemProcessRunner.swift`. Every design
choice there is about not leaking file handles, not deadlocking on pipe buffers,
and not letting a runaway plugin live forever:

- **stdout and stderr are each drained to EOF on a dedicated background read**,
  so a plugin that writes more than the pipe buffer never blocks the child.
- **The drain is byte-capped** (8 MB): output past the cap is discarded while
  still draining to EOF, so a plugin spewing forever can't grow memory without
  bound. Streaming buffers (`StreamingProcess.partial`, `StreamAccumulator`) are
  capped the same way.
- **The parent's write-end pipe handles are closed right after launch**, so the
  reads see EOF the instant the child exits — otherwise `readToEnd` would hang
  forever holding a descriptor.
- **The `withCheckedContinuation` resumes exactly once**, after three
  independent signals arrive (stdout drained, stderr drained, process exited),
  coordinated under an `NSLock` with a `pending` counter. No trailing output is
  lost and no double-resume can occur.
- **A timeout escalates SIGTERM → SIGKILL** after a grace period. Each plugin
  is spawned (`posix_spawn`) as the leader of its own process group, so a
  timeout's signals go to the whole group (`killpg`) and reach every
  descendant it backgrounded (`sleep 900 &`, a stray `curl`), not just the
  direct child. This reaping is timeout-only by design — a plugin that exits
  normally but leaves a detached helper running may intend that as a daemon.
- **A `selfRetain` keeps the run object alive** exactly for the run's duration
  and is cleared on resume, so nothing leaks and nothing is collected early.

The `soak` CI job (`Tests/VeeRuntimeTests/MemorySoakBenchmarkTests.swift`)
drives this pipeline for a sustained window and asserts bounded memory growth
*and* that refreshes keep firing.

## One menu, resolved once, rendered twice

A plugin's dropdown is an `NSMenu` (`VeeMenu/MenuBuilder`), and an `NSMenu`
cannot be hosted in a window. Everything hanging off it is `NSMenuItem`-shaped —
`NSMenuItem.view` row renderers, `NSMenuItem.sectionHeader`, `isAlternate`,
`keyEquivalent` — so none of it transfers. Two renderers is forced by AppKit,
not chosen.

What keeps them from drifting is that **neither decides anything**.
`VeePluginFormat/MenuRowSpec.swift` resolves a `[MenuNode]` into a `MenuTree`
that answers every presentation question once — which nodes become rows
(`dropdown=false`, `header=true`), whether a row acts, whether children win over
its command, which display graphic it carries, where an `alternate=` sibling
sits. Both renderers read that and assemble:

```
                     MenuTree  (VeePluginFormat, Foundation-only)
                   every decision made exactly once
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
      MenuBuilder → NSMenu            MenuSearchContentView (SwiftUI)
      native flyouts, key=,           inline disclosure, filter field
      ⌥-alternates, type-select              │
                                    ┌────────┴────────┐
                                    ▼                 ▼
                              transient          window
                              MenuSearchPanel    DetachedPluginWindows
```

It lives in `VeePluginFormat` because `VeeMenu` and `VeeUI` are siblings that
cannot see each other, and it carries **decisions, not pixels** so the parser
stays Foundation-only. Resolving text to an `NSAttributedString` and an icon to
an `NSImage` stays in `AttributedTitleFactory` / `SymbolImageFactory`, which
both renderers already called. `ProgressParams.defaultWidth` lives in the format
layer for the same reason.

Things worth knowing before changing any of it:

- **Presentations may differ in how they unfold, never in what they contain.**
  The menu bar opens a submenu as a flyout; a window opens it inline, and more
  than one branch can be open at once — that is what a window left on the
  desktop is for. Same rows, same order, same actions.
- **A live control is the one per-surface graphic.** An `NSMenu` row cannot host
  a slider, so the menu bar draws the row's display graphic and opens the
  control on click; a window draws the control in place. `MenuRowSpec` carries
  `control` separately from `accessory` so each surface can make that call
  without either re-deciding which *graphic* a row has.
- **Search is a filter over structure, not a projection to a list.**
  `MenuTreeFilter` narrows the tree to matches plus the ancestors needed to
  reach them, and reveals them. A tree cannot rank — reordering would move rows
  out from under their parents — so results keep the plugin's authored order.
  The ranked-flat projection (`MenuSearch`/`MenuFlattener`/`FlatRow`) survives
  for `vee search`, its only remaining consumer.
- **Liveness is window-only.** The panel is on screen for seconds while the user
  types; replacing its tree underneath them would move rows under the cursor.
  Only `DetachedPluginWindowModel` calls `MenuSearchViewModel.update(nodes:)`.
- **Open branches survive a refresh.** Keyed by title path and intersected with
  the keys the new tree has, so a branch that vanished — or was retitled, which
  reads the same — closes *alone* and never cascades. Title keying is imperfect
  by construction; containing the damage is the design, not a workaround.
- **Chrome belongs to the presentation, never to the content.**
  `MenuSearchContentView` carries no size and no background; the panel wraps it
  in its fixed Liquid Glass card and the window lets it fill. The same rule puts
  the *keep open* button on the panel, the pin control in the window's title
  bar, and the plugin's Refresh/Settings/Debug controls in the window's footer —
  none of them leak into the shared view, and the filter never matches them.

Counting `vee show`'s `TerminalRenderer` and the WidgetKit extension's
`WidgetNodeView`, a plugin's parsed output is rendered by four things in total.
They all consume `ParsedOutput`, and shared leaf utilities (`SymbolImageFactory`,
`ChartSegmentColor`, `ProgressParams`' gauge defaults, `ChartParams.color`) are
what keep the two that do not read `MenuTree` from disagreeing.

## Parsing: text and JSON

`OutputParser.parseAuto(_:)` is the single entry point. It tries
`JSONOutputParser` first (a plugin opts in by printing a `{"vee":1,…}` object)
and falls back to the xbar/SwiftBar text parser. Both produce the same
`ParsedOutput`, so everything downstream (`VeeMenu`, the trust scan, the debug
console, `vee render`) is format-agnostic. The parser is total: it never throws;
problems surface as `ParseDiagnostic`s shown in the per-plugin debug console.
Untrusted numeric params are validated (non-finite values rejected) and the JSON
mapping is depth-capped, so plugin output can't produce NaN geometry or overflow
the stack.

## The trust model

Vee's most defensible feature. Because plugins are un-sandboxed by design, Vee's
answer is *transparency*:

- `VeeTrust/SourceScan` scans a plugin's source for capability keywords
  (network, filesystem write, exec, env/secret access) at install time and diffs
  what it *detects* against what the plugin *declares* via `<vee.*>` tags. This
  is a best-effort static scan (it can be evaded by obfuscated code), so the UI
  frames it as advisory, not a guarantee.
- At install, the trust sheet renders that footprint in plain language.
- `VeeTrust/TrustDiff` compares an installed plugin's footprint against an
  incoming update, so "this update newly touches the network" is visible before
  you accept it.
- `VeeCatalog/PluginProvenance` records the source URL + a content hash at
  install, so a later silent local change flips the plugin to "Modified".
  Provenance verifies *integrity* (unchanged since fetch), not *authenticity*.

It is **advisory, never enforced** — consistent with the capability boundary.
The roadmap's P3 items (observed network / filesystem) move this from
self-declared toward observed, and require a real Mac + entitlements.

## The widget cross-process channel

The main app is intentionally **un-sandboxed** (it runs arbitrary plugins); the
WidgetKit / Control Center extension is **mandatorily sandboxed**. An App Group
container does **not** bridge them: a non-sandboxed process cannot write into a
group container, and a group-suite `UserDefaults` is per-container for the
sandboxed side but global for the non-sandboxed side, so the two never meet
(both confirmed on-device).

Instead the app writes a small JSON snapshot to
`~/Library/Application Support/Vee/widget-snapshot.json`, and the extension reads
it via a read-only `temporary-exception.files.home-relative-path` entitlement,
resolving the real home through `getpwuid` to escape the sandbox container
redirect. The shared model + store is `VeeWidgetShared`, kept Foundation-only so
the extension links almost nothing.

On the app side, `VeeApp/WidgetSnapshotPublisher.swift` owns the write/reload
policy: it coalesces rapid successive publishes into one write, floors how
often it asks WidgetKit to reload timelines, and prunes plugins that are no
longer loaded before the next flush. `AppController` just calls
`publish(id:name:interval:publish:)` per plugin and `setLoaded(ids:)` after a
reload — it never touches the snapshot file or `WidgetCenter` directly.

### The widget surface contract

The channel above carries more than a scrape. Every plugin run gets a
`VEE_TARGET` environment variable (`VeeRuntime/EnvironmentBuilder.swift`,
`RuntimeEnvironmentContext.target`); for a plugin declaring
`<vee.surface>both</vee.surface>`/`widget`, `PluginCoordinator` also runs a
second `RefreshTimer` on the plugin's widget-mode cadence — reusing the
plugin's filename interval, floored at 10 seconds — that invokes it with
`VEE_TARGET=widget` and parses stdout as a single JSON "card" object
(`VeePluginFormat/WidgetCardParser.swift` → `VeeWidgetShared.WidgetCard`,
schema in
[`docs/design/widget-surface-contract.md`](docs/design/widget-surface-contract.md)).
A `widget`-surface plugin builds no `StatusItemController` at all — no menu
bar presence. `PluginSnapshot.card` (snapshot v3) carries the card alongside
the scraped fields, so a `both`/`widget` plugin that hasn't produced a valid
card yet — or a `menu`-surface plugin, which never runs in widget mode —
still falls back to the Tier-0 scrape.

The extension renders `card` via `WidgetExtension/WidgetCardView.swift`,
dispatching on `card.template` into one of five native SwiftUI views
(stat/gauge/trend/list/board), each family-adaptive. A card's `refresh`/
`shortcut` action buttons can't run in the sandboxed extension process, so
they go through a **per-plugin request channel** generalizing the Darwin
notification above: `VeeWidgetShared.WidgetActionRequest` + `…Store` let the
extension's `AppIntent` write a small `{action, pluginID, actionIndex?}`
request file (a narrowly-scoped read-write sandbox exception, unlike the
read-only one for the snapshot) and signal the app, which reads, clears, and
services it — `refresh` re-runs the plugin; `run` resolves `actionIndex`
against the plugin's current card and runs its Shortcut. `href` actions skip
this entirely: the extension opens them directly via `Link`/`widgetURL`.

## Where to add things

| I want to…                              | Start in… |
| --------------------------------------- | --------- |
| Support a new menu param                | `VeePluginFormat/LineParser.swift` (`LineParams`), then `VeeMenu/MenuBuilder.swift` |
| Change how a plugin is launched         | `VeeRuntime/PluginExecutor.swift` |
| Touch process draining / timeouts       | `VeeRuntime/SystemProcessRunner.swift` |
| Add a settings surface                  | `VeeUI/…` + `VeePreferences/…` |
| Add a catalog/Discover feature          | `VeeCatalog/…` + `VeeUI/PluginBrowser*` |
| Add a trust signal                      | `VeeTrust/…` |
| Add an App Intent / Shortcuts action    | `VeeApp/VeeAppIntents.swift` |
| Change the widget card schema/templates | `VeeWidgetShared/WidgetCard.swift`, `VeePluginFormat/WidgetCardParser.swift`, `WidgetExtension/WidgetCardView.swift` |
| Change what a row *is* on every surface  | `VeePluginFormat/MenuRowSpec.swift` (`MenuTree`) |
| Change tree filtering / disclosure       | `VeeSearch/MenuTreeFilter.swift`, `VeeSearch/MenuTreeDisplay.swift` |
| Change `vee search` ranking              | `VeeSearch/MenuSearch.swift`, `VeeSearch/MenuFlattener.swift` |
| Touch the search panel or global hotkey | `VeeApp/MenuSearchPanel.swift`, `VeeApp/GlobalHotKeys.swift` |
| Add a `vee` CLI subcommand              | `Sources/VeeCLI/…` (keep `Sources/vee` thin) |

## Build & test

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full setup. In short:

```sh
swift build          # libraries + the dev `vee` executable
swift test           # all XCTest suites (keep green; TDD)
swift run vee        # run the menu-bar app for local development
```

The distributable, signed `Vee.app` is built from `project.yml` via XcodeGen +
`xcodebuild` and is exercised in CI; you rarely need it for a code change.
