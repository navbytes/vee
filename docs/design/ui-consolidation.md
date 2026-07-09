# Design: consolidating Vee's windows + fixing loading UX

Status: **proposed**. Captures an audit of Vee's current top-level windows and a
plan to (a) merge the related ones into a single sidebar window and (b) fix the
re-fetch/re-parse-on-every-open loading cost. Written before implementation so
the scope is agreed first (like [`widget-surface-contract.md`](widget-surface-contract.md)).

## Problem

Vee opens **four-plus independent top-level windows** for one workflow — manage
your plugins, find new ones, configure the app — with no shared navigation
between them, and each rebuilds its state from scratch (or the network) every
time it opens.

### Current windows (audit)

Vee is a hand-rolled AppKit menu-bar app (`Sources/vee/Vee.swift:14`,
`setActivationPolicy(.accessory)`); there is **no SwiftUI `Settings` scene**. Each
surface is a separate `NSWindow` hosting a SwiftUI view, owned by its own
singleton "window manager", and its model is built fresh in `AppController` on
open and thrown away on close.

| Window | Class | Chrome | Model lifecycle |
|---|---|---|---|
| Preferences (⌘,) | `PreferencesWindow` (`PreferencesWindow.swift:35`) | fixed 540×480, **not resizable**, tabs: General/Stores/Variables | fresh models each open |
| Plugin Manager (⌘M) | `PluginManagerWindow` (`PluginManagerWindow.swift:6`) | resizable, min 500×460, toolbar | fresh rows each open |
| Discover (⌘D) | `PluginBrowserWindow` (`PluginBrowserWindow.swift:6`) | resizable, min 760×500, **the only window with a sidebar** (`NavigationSplitView`) | fresh model each open |
| Per-plugin Settings | `SettingsWindowManager` (`SettingsWindow.swift:7`), one window **per plugin** | fixed 460×420, not resizable | fresh model each open |
| Per-plugin Debug | `DebugWindowManager` (`PluginDebugWindow.swift:7`), one window **per plugin** | resizable 580×540 | model cached on coordinator, live-updating |

Menu wiring is a static `NSMenu` (`MainMenuController.swift:31-45`): Preferences
⌘,, Plugin Manager ⌘M, Discover ⌘D.

### The loading cost

Because every model is rebuilt on open and nothing is cached across opens:

- **Discover re-fetches the whole catalog from the network on every open.** The
  fetch fires from `.task { if entries.isEmpty { await load() } }`
  (`PluginBrowserView.swift:370`), and `entries` is always empty because the
  model is new (`AppController.openBrowser`). Plus per-card GitHub calls —
  `loadHeader` (source fetch) and `loadLastUpdated` (one commits-API call each,
  rate-limit-sensitive) — whose caches (`headers`, `trustLevels`, `lastUpdated`)
  die with the model. Nothing survives a close/reopen.
- **Opening the Manager re-reads and re-parses every plugin on the main thread.**
  `AppController.managerRows()` (`AppController.swift:659-691`) does
  `String(contentsOfFile:)` + `HeaderParser.parse` + `TrustAnalyzer.analyze` per
  plugin, synchronously, called straight from the ⌘M menu action.
- **The Manager doesn't live-refresh** when plugins change on disk (only the
  per-row error badge updates). Rows are frozen for the window's lifetime.

### Duplication / seams

- General settings (folder chooser + launch-at-login) appear in **both**
  Preferences → General and the Manager (shared `GeneralSettingsContent`,
  `GeneralSettingsView.swift:38`).
- **Three** install-trust UIs: `InstallTrustSheet` (Discover), an `NSAlert`
  (`AppController.confirmInstall`, for `swiftbar://addplugin`), and differing
  capability text.
- Inconsistent chrome: Preferences and per-plugin Settings are fixed-size;
  everything else resizable. Sizes hardcoded in the SwiftUI views.

## Key insight

The two problems share **one root cause**: there is no persistent app-level UI
model. Everything is per-window, built on open, discarded on close. So a single
change — **introduce a retained app-level model that owns the catalog cache and
the installed-plugin rows** — both fixes the loading cost *and* provides the
shared state a consolidated window needs. The consolidation and the loading fix
are the same architectural move.

## Decision

### 1. One window, sidebar-navigated

Merge the three "library" surfaces into a single window, reusing the
`NavigationSplitView` shell Discover already has
(`PluginBrowserView.swift:342`). Sidebar sections:

```
  Vee
  ┌───────────────┬──────────────────────────────┐
  │ Installed     │                              │
  │ Discover      │      detail / grid            │
  │ ───────────   │                              │
  │ Variables     │   selecting an installed      │
  │ Stores        │   plugin → Settings · Debug   │
  │ General       │   tabs in the detail pane      │
  └───────────────┴──────────────────────────────┘
```

- **Installed / Discover / Variables / Stores / General** become sidebar
  sections — the System-Settings / App-Store pattern, one place for the whole
  workflow.
- **Per-plugin Settings and Debug** move into the detail pane (or an inspector)
  when a plugin is selected, retiring `SettingsWindowManager` and the per-plugin
  window sprawl. Debug may optionally "pop out" as its own resizable window (it's
  a live log).
- Shortcuts preserved: ⌘, → focus General, ⌘M → Installed, ⌘D → Discover — same
  muscle memory, one window.
- Collapses the duplicated General settings and unifies chrome (resizable, one
  size).

### 2. Persistent app-level model + caching

- A retained `LibraryModel` (name TBD) on `AppController`, holding the fetched
  catalog `entries` + the per-plugin `headers`/`trustLevels`/`lastUpdated`
  caches, keyed by a **signature** of (enabled stores, plugins directory). On
  open, seed the view from cache (instant), then refresh in the background;
  invalidate when the signature changes (preserving today's "swap fresh model so
  a changed store/dir takes effect" invariant, `PluginBrowserWindow.swift:16`).
- Build the installed rows **off the main thread** (and/or from the coordinators'
  already-parsed headers instead of re-reading disk), so navigating to Installed
  is instant with async population.
- **Live-refresh Installed** by wiring the existing `PluginDirectoryWatcher`
  (`AppController.swift:136`) to the model, so added/removed/edited plugins
  appear without a reopen.

### 3. Unify install-trust UI

Route `swiftbar://addplugin` through the same `InstallTrustSheet` as Discover,
retiring the `NSAlert` path, so the trust gate looks and behaves the same
everywhere.

## What makes this easy vs. hard

**Easy:** views are already SwiftUI in `NSHostingController`; the sidebar shell
already exists in Discover; General settings are already a shared reusable view
(`GeneralSettingsView.swift:38`).

**Hard:** there are **no shared/persistent models today** — five singleton window
managers, models rebuilt per open. The work is concentrated in `AppController`'s
open-methods and introducing the retained model; the SwiftUI views mostly move,
not change.

## Phasing (each a reviewable PR)

1. **Loading foundation (no visible re-layout).** Add the retained app-level
   model + catalog cache across opens; move `managerRows()` off the main thread;
   persist the per-plugin lazy caches. The existing windows just get fast. This
   is the no-regret step and the prerequisite for the shell.
2. **The shell.** One sidebar window hosting Installed / Discover / Settings;
   fold per-plugin Settings/Debug into the detail pane; preserve the ⌘,/⌘M/⌘D
   entry points; retire the extra window managers.
3. **Polish.** Live-refresh Installed via the directory watcher; unify the
   install-trust UI; consistent chrome; skeleton/optimistic loading states.

## Open questions

1. **Per-plugin Settings/Debug in-pane vs. separate windows** — fold both into
   the detail pane, or keep Debug as a pop-out log window? (Leaning: Settings
   in-pane, Debug in-pane with optional pop-out.)
2. **Does Preferences stay a distinct ⌘, window** per macOS convention, or become
   a sidebar section? (Leaning: sidebar section, with ⌘, focusing it — the
   settings are mostly *about* plugins, so they belong with the library.)
3. **Scope of phase 1** — catalog cache only, or catalog + off-main Manager rows
   together?
