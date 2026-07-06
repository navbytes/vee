# Vee roadmap — becoming the category leader

This document is a prioritized product strategy for making Vee the best
menu-bar script runner on macOS. It is grounded in a competitive analysis of
xbar and SwiftBar (feature surface, open issues, community sentiment) and the
platform capabilities available on macOS 26 (Tahoe).

Status legend: ✅ shipped · 🟡 partial (baseline exists, gap remains) · ⬜ open.
Each ⬜/🟡 item is scoped to be a single, self-contained commit on the PR so
progress is reviewable step by step.

## Where the category stands

- **xbar** owns the largest plugin catalog (`matryer/xbar-plugins`) but is
  effectively unmaintained — the latest release is a 2021-era beta, and the
  project has publicly asked for maintainers. Its users are a large, migratable
  base.
- **SwiftBar** is the actively-developed leader: native Swift, SF Symbols,
  streaming, Shortcuts-type plugins. But it still fights the category's core
  reliability bugs and invests little in configuration UX or a curated catalog.
- **Sketchybar** owns the power-user/tiling-WM end — gorgeous and event-driven,
  but config-as-code only, with a steep learning curve and no GUI.

The unoccupied quadrant is **reliable + approachable + trustworthy + modern**:
SwiftBar's ease with Sketchybar's polish, plus a real trust/secrets story and
2026 platform integration. That is Vee's target.

## What the incumbents get wrong (ranked by churn impact)

1. **Reliability after sleep/wake and long uptime.** The #1 complaint for both
   apps: plugins silently stop refreshing after sleep/lock; only a relaunch
   fixes it (SwiftBar #179/#390, xbar #807/#780).
2. **Memory / CPU creep.** Unbounded growth over hours (xbar #725, SwiftBar
   #488/#392).
3. **The menu-bar item disappears** or never appears (SwiftBar #442).
4. **A slow script freezes the UI** — no async/timeout model.
5. **PATH / interpreter hell** — "works in Terminal, not in the launcher"
   (xbar #856/#808/#730). The single biggest first-run friction.
6. **Secrets live in plaintext** plugin files.
7. **No trust/security posture** for running arbitrary community scripts.
8. **Menu-bar overflow / notch** hides items with no ordering control.

Vee's architecture already answers 1–4 and 6–7 by design (async runs with
hard timeouts and SIGTERM→SIGKILL, incremental output draining, set-diffed
reloads, energy-aware background scheduling, Keychain-backed secrets, and a
`<vee.*>` trust layer). **That is the moat — it must be proven and marketed,
not just built.**

## The three differentiation wedges

Everything below rolls up to three bets. Ranked by how hard they are for an
incumbent to copy:

1. **Verified trust** — move the `<vee.*>` trust layer from *self-declared* to
   *observed*. Record what a plugin actually touches and diff it against what it
   declared. No competitor has anything in this space; it is the only truly
   novel feature and should carry the product narrative.
2. **A proven reliability moat** — the async/timeout/wake-refresh architecture
   already beats both incumbents on their #1 and #2 churn complaints. It must be
   *demonstrated* with a public, reproducible soak benchmark, not just asserted.
3. **Native 2026 platform leap** — App Intents, Control Center Controls, Focus
   filters, WidgetKit, and Liquid Glass interactive popovers. The "modern" wedge,
   and the on-brand answer to "rich UI" (see the decision note below).

## Priorities

### P0 — Table stakes & credibility

- **Complete xbar/SwiftBar parameter compatibility.** Drop-in migration is the
  acquisition wedge, so every documented parameter must actually work.
  - ✅ `key=` menu-item keyboard shortcuts (`VeeMenu/KeyEquivalent.swift`).
  - ✅ `shortcut=` runs a macOS Shortcut (`VeeApp/AppActionDispatcher.swift`).
  - ✅ `dropdown=false` honored (`VeeMenu/MenuBuilder.swift`).
  - ✅ clickable `notify?href=` (`VeeApp/Notifier.swift`).
  - ✅ `sfconfig` SF Symbol scale/weight (`VeeMenu/SFSymbolConfig.swift`).
  - ✅ `webview=` opens a standalone WebView window, kept out of the menu
    itself to preserve the leak-free guarantee (`VeeApp/WebViewPresenter.swift`).
  - ✅ `<swiftbar.hideRunInTerminal/hideLastUpdated/hideDisablePlugin/hideSwiftBar>`
    parsed; per-plugin "Updated <time>" line honoring `hideLastUpdated`.
- ✅ **Deterministic environment.** Login-shell `PATH` resolution + Homebrew
  backstop so plugins that work in Terminal work in Vee
  (`VeeRuntime/ShellPathResolver.swift`).
- ✅ **Refresh on wake** with a regression test (`VeeApp/WakeMonitor.swift`,
  `WakeMonitorTests`).
- ✅ **`swiftbar://` API parity.** `addplugin?src=…` and `setephemeralplugin`.
- 🟡 **Prove reliability with a public soak benchmark.** Harness + CI job
  shipped: `Tests/VeeRuntimeTests/MemorySoakBenchmarkTests.swift` drives the real
  execution/refresh pipeline (`RefreshTimer` → `PluginExecutor` →
  `SystemProcessRunner` → `StreamAccumulator`) for a configurable window,
  sampling RSS via `task_info`/`mach_task_basic_info` and asserting bounded memory
  growth *and* that refreshes keep firing (no silent stall). It is opt-in
  (`VEE_SOAK=1`) so it never slows normal `swift test`, and runs as its own
  nightly/dispatch CI job (`.github/workflows/ci.yml`, job `soak`, on `macos-26`).
  Still open: publish the RSS/CPU-over-time graph and the "Vee vs SwiftBar after
  24h" comparison on the docs landing page. _(follow-up commit wires the published
  chart into the docs site.)_

### P1 — Clear superiority

- ✅ **App-wide Preferences window + first-class Variables/config UX.** A
  standard ⌘, Preferences window (`VeeUI/PreferencesWindow.swift`) with a
  **General** tab that reuses the app-level settings — plugins-folder chooser,
  launch-at-login, refresh-all, open-folder — factored into a shared
  `GeneralSettingsContent`/`GeneralSettingsTab` (`VeeUI/GeneralSettingsView.swift`)
  now used by both Preferences and the Plugin Manager — and a **Variables** tab
  (`VeeUI/VariablesEditorView.swift`) that aggregates every installed plugin's
  declared `<xbar.var>` variables, grouped by plugin, each editable, with secret
  fields masked and stored in the Keychain. The pure, unit-tested aggregation
  (`VeePreferences/VariableAggregator.swift`: `AggregatablePlugin` →
  `VariableDeclarationReading` → `PluginVariableGroup`, tests in
  `Tests/VeePreferencesTests/VeePreferencesTests.swift`) reuses `VarStore` and
  `SecretStore` for persistence and supersedes xbar's per-plugin `xbar.var` GUI.
  ⌘, is wired through a hidden AppKit app menu (`VeeApp/AppController.swift`,
  `VeeApp/MainMenuController.swift`). _(1 commit.)_
- ✅ **Catalog updates** in Discover: one-click, trust-gated update for installed
  plugins (`VeeUI/PluginBrowserView.swift`).
- ✅ **Catalog quality signals.** Last-updated + freshness badges ship on
  Discover cards. `CatalogEntry` gained an optional `lastUpdated: Date?`
  (`VeeCatalog/CatalogEntry.swift`), populated lazily via a new
  `CatalogFetching.fetchLastUpdated(_:)` that hits the GitHub commits API one
  call per plugin (`VeeCatalog/CatalogClient.swift`, parsed by
  `CatalogParser.parseLastCommitDate`). A pure, unit-tested
  `PluginFreshness.classify(lastUpdated:now:)` (`VeeCatalog/PluginFreshness.swift`,
  fresh <6mo / aging 6mo–2y / stale >2y) tints an "Updated 3y ago" badge that
  the card loads lazily on appear (`VeeUI/PluginBrowserView.swift`). A "works on
  your macOS" badge was intentionally **omitted**: that compatibility data is not
  sourceable from the xbar git-tree catalog (paths only, no runtime/OS metadata),
  so shipping it would mean fabricating a signal. Turns the migratable xbar base
  into Vee's base.
- ✅ **In-app debugging.** Per-plugin debug console (`VeeUI/PluginDebugView.swift`).
- ✅ **Menu-bar ordering** persists across relaunch via a stable autosave name.
  Notch-aware overflow handling folds into Control Center Controls (P2). 
- ✅ **Shortcuts / App Intents integration.** Refresh-all / refresh-one /
  enable-disable exposed as `AppIntent`s (`VeeApp/VeeAppIntents.swift`).
  Rendering a user Shortcut's output remains open. _(1 commit when picked up.)_

### P2 — 2026 platform leap (native rich UI)

This is where "rich, interactive plugin UI" gets delivered — natively, without
an embedded cross-platform runtime (see the decision note below). Menu rendering
today is plain native `NSMenu` (`VeeMenu/MenuBuilder.swift`); none of the items
below exist yet in `Sources/`.

- ✅ **Liquid Glass `.window`-style interactive popovers** with inline
  charts/toggles/sliders, so common rich UIs no longer need a WebView. This is
  the on-brand answer to the RN/Flutter question. Two kinds ship, both kept out
  of the `NSMenu` (like the WebView window) so the menu stays native and
  leak-free:
  - **Read-only sparkline.** A dropdown item carrying `sparkline=1,2,3` (parsed
    to `[Double]` on `LineParams`, `VeePluginFormat/LineParser.swift`) opens a
    native `NSPopover` (`VeeApp/PluginPopover.swift`) hosting a SwiftUI Swift
    Charts line/area sparkline on a Liquid Glass surface
    (`VeeUI/SparklineChartView.swift`).
  - **Interactive controls.** An item carrying `toggle=on` or
    `slider=min,max,value` (parsed to a `PluginControl` on `LineParams`) opens a
    Liquid Glass control popover (`VeeUI/PluginControlView.swift`). Committing a
    value re-invokes the item's `shell=`/`bash=` command with the value provided
    both as `VEE_CONTROL_VALUE` and as a trailing argument, then refreshes if
    `refresh=true`. The value→command contract is a pure, unit-tested core
    (`VeeApp/ControlReinvocation.swift`, `Tests/VeeAppTests/ControlReinvocationTests.swift`);
    the parser is covered by `Tests/VeePluginFormatTests/ControlParamTests.swift`.
    _(1 commit.)_
- ✅ **WidgetKit widget + Control Center control.** A signed `app-extension`
  target (`WidgetExtension/`, wired in `project.yml`) ships both a WidgetKit
  widget that surfaces current plugin output on the desktop / Notification Center
  (`PluginStatusWidget`, small/medium/large families) and a `ControlWidget` that
  refreshes every plugin from Control Center (`RefreshAllControl`), gated
  `@available(macOS 26.0, *)` inside the `WidgetBundle`. Verified on-device: the
  widget renders live plugin values and the control refreshes.
  - **The cross-process channel is the interesting part.** Vee's app is
    intentionally un-sandboxed (it runs arbitrary plugins); the widget extension
    is mandatorily sandboxed. An **App Group does not work** here — a
    non-sandboxed process cannot write into a group container
    (`NSCocoaError 513`), and a group-suite `UserDefaults` is scoped per-container
    for the sandboxed side but globally for the non-sandboxed side, so the two
    never meet (both empirically confirmed on-device). Instead the app writes a
    small JSON snapshot to `~/Library/Application Support/Vee/widget-snapshot.json`
    (which it can, being un-sandboxed) and the widget reads it via a read-only
    `temporary-exception.files.home-relative-path` entitlement — resolving the
    real home through `getpwuid` so the sandboxed side escapes its container
    redirect. The shared model + store is a dependency-free module
    (`Sources/VeeWidgetShared/`, unit-tested). This keeps CI green (ad-hoc /
    `CODE_SIGNING_ALLOWED=NO`) since no provisioned capability is needed.
  - The control signals a running app via a Darwin notification and launches a
    closed one via `openAppWhenRun` (which refreshes all plugins on startup), so
    no shared request-flag is needed. _(1 commit.)_
- ⬜ **Focus filters** (`SetFocusFilterIntent`) to show/hide plugin groups per
  Focus mode (Work/Personal/DND). _(1 commit.)_
  **→ Deferred to local macOS development** (App Intents extension + entitlements).
- ✅ **Actionable, time-sensitive notifications** (Re-run / Silence / Open log
  buttons) for monitor-style plugins. A plugin passes `swiftbar://notify?plugin=…`
  to get a `VEE_PLUGIN_ALERT` `UNNotificationCategory` with Re-run / Silence /
  Open-log `UNNotificationAction`s and a `.timeSensitive` interruption level;
  Silence tracks a per-session suppressed set that skips future alerts. Implemented
  in `Sources/VeeApp/Notifier.swift` (category, actions, `NotificationSuppressor`,
  `NotificationRouter`), `Sources/VeeApp/URLActionRouter.swift` (`plugin=` param),
  `Sources/VeeApp/AppController.swift` (wires Re-run→refresh, Open-log→debug console),
  and `Sources/VeeApp/PluginCoordinator.swift` (`showDebugConsole()`). _(1 commit.)_

### P3 — The verified-trust moat

The trust layer is Vee's most defensible, category-defining feature. Today it is
**static and self-declared**: `VeeTrust/SourceScan.swift` scans plugin source for
capability keywords at install time and diffs detected-vs-declared. The leap is
to make trust **observed at runtime** and to make *changes* to a plugin's
footprint visible.

- ✅ **Trust diff on update.** When Discover updates an installed plugin, show a
  diff of its declared/detected capabilities ("this update adds filesystem-write
  and a new domain"). Reuses the existing `SourceScan` — the highest-value,
  lowest-cost step; do this first. _(1 commit.)_ (VeeTrust/TrustDiff.swift)
- ⬜ **Observed network.** Record the domains a plugin actually connects to (a
  lightweight local resolver/proxy shim around plugin subprocesses) and diff
  against `<vee.network>` declarations; surface undeclared connections in the
  Manager. _(1–2 commits.)_
  **→ Deferred to local macOS development** (subprocess network interception
  needs a real run environment; not meaningfully testable in CI).
- ⬜ **Observed filesystem/exec** via Endpoint Security (or an entitlement-gated
  observer) to flag reads/writes/exec beyond what was declared. Advisory, never
  enforced — consistent with the existing trust philosophy. _(later; larger.)_
  **→ Deferred to local macOS development** (Endpoint Security requires a
  provisioned entitlement + a signed build; cannot function in CI).
- ✅ **Provenance for catalog plugins.** Record source URL + content hash at
  install so a later silent change (local tampering or a re-install from a
  different source) is detectable, and surface a Verified/Modified indicator on
  installed plugins. _(1 commit.)_ (VeeCatalog/PluginProvenance.swift,
  VeeUI/PluginBrowserView.swift)

### P4 — Authoring reach (typed SDKs, not UI frameworks)

- ✅ Zero-dependency **TypeScript SDK** with a golden-fixture drift guard
  (`plugins/`).
- ✅ **Typed SDKs in more languages** — Python + Go builders that emit the same
  protocol, each with its own golden-fixture guard mirroring the TS setup. This
  gives authors the ergonomics people imagine they want from "Flutter/React
  Native" (typed, structured output) with none of the runtime cost. (A Swift
  builder remains a possible future addition.)
  - ✅ **Python SDK** — `plugins/python/` (`vee.py` Menu/Section builders,
    `unittest` drift guard reusing the TS golden fixtures byte-for-byte; CI job
    "Plugin SDK (Python)").
  - ✅ **Go SDK** — `plugins/go/` (`vee.go` Menu/Section builders, `go test`
    drift guard against the shared fixture; CI job "Plugin SDK (Go)").

## Decision note — React Native / Flutter

**Not planned, by design.** A Vee plugin only emits the xbar/SwiftBar text
protocol to stdout; Vee renders the menu natively (`NSMenu`). React Native and
Flutter are UI-*rendering* frameworks whose entire value is their render engine —
which Vee does not and cannot use for the menu bar. The three ways one might
"add" them all lose:

- **As a plugin language:** pointless — you can already run any interpreter
  (`node`, `dart`, `python`); the framework's renderer adds nothing over stdout.
- **Embedded in the menu/popover for rich UI:** self-defeating — it reintroduces
  exactly the heavyweight-runtime memory problem Vee is built against, adds a
  large dependency to a proudly zero-dependency app, and dilutes the pure
  Swift/AppKit identity. The genuine need (rich, interactive UI) is met natively
  by the P2 Liquid Glass popovers and WidgetKit items.
- **As a cross-platform rewrite:** throws away the entire moat — SF Symbols, App
  Intents, Control Center, Focus filters, Liquid Glass, Keychain, Endpoint
  Security. Those deep macOS-26 integrations *are* the product.

So "rich UI" is delivered the native way (P2), and broader authoring reach is
delivered via typed SDKs in more languages (P4) — not by embedding a
cross-platform UI framework.

## Execution status & handoff (PR #15)

The roadmap above was executed step by step on the
`claude/project-differentiation-research-c97pjh` branch, one commit per step,
each validated by CI on `macos-26` (Swift) or a language job (SDKs).

**Shipped on this PR:**

1. Trust diff on update (P3) — `VeeTrust/TrustDiff.swift`
2. Reliability soak harness + CI job (P0) — `Tests/VeeRuntimeTests/MemorySoakBenchmarkTests.swift`, CI `soak`
3. Catalog last-updated + freshness badges (P1) — `VeeCatalog/PluginFreshness.swift`
4. App-wide Preferences window + cross-plugin Variables editor (P1) — `VeeUI/PreferencesWindow.swift`, `VeePreferences/VariableAggregator.swift`
5. Liquid Glass sparkline popover (P2, partial) — `VeeUI/SparklineChartView.swift`, `VeeApp/PluginPopover.swift`
6. Actionable, time-sensitive notifications (P2) — `VeeApp/Notifier.swift`
7. Catalog provenance / modified-plugin flag (P3) — `VeeCatalog/PluginProvenance.swift`
8. Python plugin SDK (P4) — `plugins/python/`
9. Go plugin SDK (P4) — `plugins/go/`

**Shipped since PR #15, on a real Mac** (built, signed, and exercised on
Apple-Silicon macOS 26 — the local-development handoff the items below waited on):

- Interactive toggle/slider control popovers (P2 follow-up) — `VeeUI/PluginControlView.swift`, `VeeApp/ControlReinvocation.swift`.
- WidgetKit widget + Control Center control (P2) — `WidgetExtension/`, `Sources/VeeWidgetShared/`. On-device verified; uses a file + temporary-exception channel (App Groups don't work for a non-sandboxed writer — see P2 above).

**Still deferred to local macOS development** (each needs a new signed Xcode
extension target and/or provisioned entitlements only exercisable on a real Mac):

- Focus filters (P2) — App Intents extension.
- Observed network (P3) — subprocess network interception.
- Observed filesystem/exec via Endpoint Security (P3) — provisioned entitlement + signed build.
- Published soak chart / "Vee vs SwiftBar after 24h" on the docs site (P0 follow-up).

## Positioning

xbar is abandoned but owns the catalog; SwiftBar is maintained but native-dated,
config-thin, and still fighting reliability bugs. Vee wins by being (a) a
drop-in for both, (b) demonstrably more reliable and non-blocking (proven by a
public soak benchmark), (c) the first to adopt 2026 macOS surfaces — App Intents,
Control Center Controls, Focus filters, widgets, Liquid Glass — and (d) the only
one with a real trust story that moves from self-declared to *verified*, plus
Keychain-secured config and a curated, trust-gated catalog that neither incumbent
does well.
