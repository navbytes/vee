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
- ⬜ **Prove reliability with a public soak benchmark.** A CI job (or a
  documented, scripted local harness) that runs N plugins for many hours and
  publishes an RSS/CPU-over-time graph, plus a "Vee vs SwiftBar after 24h"
  comparison on the landing page. Reliability is built; it must be *proven*.
  _(1 commit: add the soak harness + CI job; a follow-up commit wires the
  published chart into the docs site.)_

### P1 — Clear superiority

- 🟡 **App-wide Preferences window + first-class Variables/config UX.**
  Per-plugin settings and a Plugin Manager already exist
  (`VeeUI/PluginManagerView.swift`, `PluginSettingsView.swift`) with
  Keychain-backed secret fields (`VeePreferences/SecretStore.swift`). Still
  open: a dedicated app-wide Preferences window and a top-level Variables editor
  that supersedes xbar's `xbar.var` GUI (today vars are per-plugin sidecars via
  `VarStore`). _(1 commit.)_
- ✅ **Catalog updates** in Discover: one-click, trust-gated update for installed
  plugins (`VeeUI/PluginBrowserView.swift`).
- ⬜ **Catalog quality signals.** Add last-updated / "works on your macOS" /
  freshness badges to catalog cards. `CatalogEntry` currently carries only
  path/category/filename/rawURL — it needs version/date/compat fields and badge
  rendering. Turns the migratable xbar base into Vee's base. _(1 commit for the
  model + parse fields, 1 commit for badge rendering.)_
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

- ⬜ **Liquid Glass `.window`-style interactive popovers** with inline
  charts/toggles/sliders, so common rich UIs no longer need a WebView. This is
  the on-brand answer to the RN/Flutter question. _(Land incrementally: (1) an
  `NSPopover`-based rich surface behind a plugin opt-in header, (2) inline
  Swift Charts sparkline/series rendering, (3) interactive toggle/slider items
  that re-invoke the plugin with a param.)_
- ⬜ **Control Center Controls** (`ControlWidget` +
  `AppIntentControlConfiguration`) so plugin actions live in Control Center and
  can be dragged to the menu bar — a native answer to menu-bar overflow.
  (Verify on current 26.x; third-party controls were flaky at Tahoe launch.)
  _(1 commit for a Widget/Control extension target + a first control.)_
- ⬜ **Focus filters** (`SetFocusFilterIntent`) to show/hide plugin groups per
  Focus mode (Work/Personal/DND). _(1 commit.)_
- ⬜ **Interactive WidgetKit widgets** surfacing plugin output on the desktop and
  in Notification Center. _(1 commit for the widget extension + a timeline
  provider reading plugin output.)_
- ⬜ **Actionable, time-sensitive notifications** (Re-run / Silence / Open log
  buttons) for monitor-style plugins. `Notifier.swift` posts content + href
  today; this adds `UNNotificationAction` categories and interruption levels.
  _(1 commit.)_

### P3 — The verified-trust moat

The trust layer is Vee's most defensible, category-defining feature. Today it is
**static and self-declared**: `VeeTrust/SourceScan.swift` scans plugin source for
capability keywords at install time and diffs detected-vs-declared. The leap is
to make trust **observed at runtime** and to make *changes* to a plugin's
footprint visible.

- ⬜ **Trust diff on update.** When Discover updates an installed plugin, show a
  diff of its declared/detected capabilities ("this update adds filesystem-write
  and a new domain"). Reuses the existing `SourceScan` — the highest-value,
  lowest-cost step; do this first. _(1 commit.)_
- ⬜ **Observed network.** Record the domains a plugin actually connects to (a
  lightweight local resolver/proxy shim around plugin subprocesses) and diff
  against `<vee.network>` declarations; surface undeclared connections in the
  Manager. _(1–2 commits.)_
- ⬜ **Observed filesystem/exec** via Endpoint Security (or an entitlement-gated
  observer) to flag reads/writes/exec beyond what was declared. Advisory, never
  enforced — consistent with the existing trust philosophy. _(later; larger.)_
- ⬜ **Provenance for catalog plugins.** Record source URL + content hash at
  install so a later silent upstream change is detectable. _(1 commit.)_

### P4 — Authoring reach (typed SDKs, not UI frameworks)

- ✅ Zero-dependency **TypeScript SDK** with a golden-fixture drift guard
  (`plugins/`).
- ⬜ **Typed SDKs in more languages** — Python, Go, and/or Swift builders that
  emit the same protocol, each with its own golden-fixture guard mirroring the
  TS setup. This gives authors the ergonomics people imagine they want from
  "Flutter/React Native" (typed, structured output) with none of the runtime
  cost. _(1 commit per language.)_

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

## Positioning

xbar is abandoned but owns the catalog; SwiftBar is maintained but native-dated,
config-thin, and still fighting reliability bugs. Vee wins by being (a) a
drop-in for both, (b) demonstrably more reliable and non-blocking (proven by a
public soak benchmark), (c) the first to adopt 2026 macOS surfaces — App Intents,
Control Center Controls, Focus filters, widgets, Liquid Glass — and (d) the only
one with a real trust story that moves from self-declared to *verified*, plus
Keychain-secured config and a curated, trust-gated catalog that neither incumbent
does well.
