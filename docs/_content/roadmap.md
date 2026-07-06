# Vee roadmap — becoming the category leader

This document is a prioritized product strategy for making Vee the best
menu-bar script runner on macOS. It is grounded in a competitive analysis of
xbar and SwiftBar (feature surface, open issues, community sentiment) and the
platform capabilities available on macOS 26 (Tahoe).

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

## Priorities

### P0 — Table stakes & credibility

- **Complete xbar/SwiftBar parameter compatibility.** Drop-in migration is the
  acquisition wedge, so every documented parameter must actually work.
  - ✅ `key=` menu-item keyboard shortcuts (shipped).
  - ✅ `shortcut=` runs a macOS Shortcut (shipped).
  - ✅ `dropdown=false` honored (shipped).
  - ✅ clickable `notify?href=` (shipped).
  - ☐ `sfconfig` SF Symbol rendering mode/scale/weight.
  - ☐ `webview=` popover (a `.window`-style WebView, kept out of the menu
    itself to preserve the leak-free guarantee) — or formally drop it.
  - ☐ `<swiftbar.hideRunInTerminal/hideLastUpdated/hideDisablePlugin>` header
    family; a per-plugin "last updated" line.
- **Deterministic environment.** Resolve the login-shell `PATH` and detect
  Homebrew / pyenv / asdf / nvm interpreters so plugins that work in Terminal
  work in Vee. This is the highest-leverage reliability fix for new users.
- **Prove reliability.** An explicit sleep/wake re-arm path with a regression
  test, and a long-running soak test in CI, so "leak-free, survives sleep" is a
  claim backed by evidence.
- **`swiftbar://` API parity.** Add `addplugin?src=…` (one-click install from a
  link) and `setephemeralplugin` (transient menu content without a file).

### P1 — Clear superiority

- **App-wide Preferences window** and a first-class **Variables/config UX** that
  supersedes xbar's `xbar.var` GUI, with Keychain-backed secret fields (Vee
  already has the storage; it needs the top-level surface).
- **Catalog quality signals** in Discover: last-updated, works-on-this-macOS
  badges, and **update notifications / one-click update** for installed
  plugins (currently install-only).
- **In-app debugging.** Surface the parse diagnostics Vee already collects, plus
  a live stdout/stderr/exit-code console and a "dry run" — directly answering
  "why did my plugin fail?"
- **Menu-bar ordering & overflow** that persists across relaunch and is
  notch-aware, so users don't need Bartender/Ice.
- **Deep Shortcuts / App Intents integration.** Model core actions (refresh,
  enable/disable, run plugin) as `AppIntent`s so they appear in Shortcuts and
  Spotlight; let a plugin render a user Shortcut's output.

### P2 — 2026 platform leap

- **Control Center Controls** (`ControlWidget` + `AppIntentControlConfiguration`)
  so plugin actions can live in Control Center and be dragged to the menu bar —
  a native answer to the overflow problem. (Verify on current 26.x; third-party
  controls were flaky at Tahoe launch.)
- **Focus filters** (`SetFocusFilterIntent`) to show/hide plugin groups per
  Focus mode (Work/Personal/DND).
- **Interactive WidgetKit widgets** surfacing plugin output on the desktop and
  in Notification Center.
- **Actionable, time-sensitive notifications** (Re-run / Silence / Open log
  buttons) for monitor-style plugins.
- **Liquid Glass** `.window`-style popovers with inline charts/toggles/sliders,
  so common rich UIs no longer need a WebView.

## Positioning

xbar is abandoned but owns the catalog; SwiftBar is maintained but native-dated,
config-thin, and still fighting reliability bugs. Vee wins by being (a) a
drop-in for both, (b) demonstrably more reliable and non-blocking, (c) the first
to adopt 2026 macOS surfaces — App Intents, Control Center Controls, Focus
filters, widgets, Liquid Glass — while adding the Keychain-secured config and
curated, trust-gated catalog that neither incumbent does well.
