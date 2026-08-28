# Design: plugin-bar-placement

## Context

One boolean drives everything today. `StatusItemController` owns either an
`NSStatusItem` (standalone) or an `NSMenuItem` row in
`CompactMenuBarController`'s shared menu; `reconcileMode()`
(`Sources/VeeApp/StatusItemController.swift:442`) switches between them live on
a notification and repaints the last render onto the new surface
(`repaintCurrentSurface()`, `:463`). `AppController.applyCompactMode` (`:243`)
hides `MainMenuController`'s item and installs its rows as a footer under the
shared item, so two Vee icons are never both present.

`StatusItemController` is also the hub for every *non*-bar surface: it drives
`DetachedPluginWindows.show`/`update`/`markFresh`/`markStale` (`:226`, `:289`,
`:300`, `:333`) and presents `MenuSearchPanel` (`:253`). That single fact
decides Decision 3 below.

**No spec deltas in this change.** The `openspec` CLI is not installed in this
environment, so nothing would validate, sync, or archive `specs/` files;
`.openspec.yaml` declares `skip_specs: true`. This document plus `tasks.md` are
the authority, and the behavioural contract lives as the acceptance checks
attached to each task.

## Goals / Non-Goals

**Goals:**
- One resolved placement per plugin, decided in one place, switchable live.
- Migration that changes no observable behaviour for an existing install.
- `hidden` costs a plugin its bar presence and nothing else.

**Non-Goals:**
- Named groups / multiple shared icons. The stored value is *shaped* so they
  are additive later (Decision 2), but no multi-group UI here.
- Letting a user override a plugin's `<vee.surface>` (e.g. to get a widget card
  from a `.menu`-only plugin). Real gap, different change — it alters the
  execution model, not the presentation.
- Author-declared placement, in any form.
- Attention-based promotion — `plugin-attention-promotion`, which depends on
  this landing first.

## Decisions

### 1. Placement replaces the boolean at the same seam

`reconcileMode()` already tears down one surface, builds the other, and
repaints. It becomes `reconcilePlacement()` over a three-valued placement
instead of a `Bool`, so every existing live-switch guarantee comes along
unchanged.

*Rejected:* rebuilding the controller on a placement change — it would drop
`lastRendered`, the detached window's registration, and the plugin's schedule,
all of which the in-place switch preserves.

### 2. The stored value is shaped for groups

```swift
// Sources/VeePreferences/BarPlacement.swift  (new, VeePreferences)
public enum BarPlacement: Equatable, Sendable {
    case own                      // its own NSStatusItem
    case folded(group: String)    // a row under a shared item; "Vee" is the only group today
    case hidden                   // no menu-bar presence

    public static let defaultGroup = "Vee"
    public static let foldedDefault = BarPlacement.folded(group: defaultGroup)
}
```

Encoded as `"own"` / `"folded:Vee"` / `"hidden"`. The UI exposes three choices;
the model grows a named-group value later with no second migration — which is
what the roadmap's Focus filters need. A flat three-case enum costs the same to
store and forecloses that.

### 3. `hidden` keeps the controller and the run; only the bar surface goes

Both `statusItem` and `compactEntry` are nil — a third branch in
`applyPresentation` (`:546`), `applyMenu` (`:594`) and `applyAlpha` (`:607`),
all of which already branch on which surface exists. `render(_:)` still stores
`lastRendered`, still updates detached windows, still publishes the widget
scrape.

Explicitly **not** the `<vee.surface>widget` path, which nils the controller
(`PluginCoordinator.swift:111`) and skips the menu-mode run and schedule
(`:223`). That path exists for a plugin that never had a menu; reusing it would
silently kill the window, panel, and freshness surfaces a hiding user is
relying on.

### 4. The two Vee items become one home item

`CompactMenuBarController` becomes the sole owner of Vee's status item, always
present, with the app-controls footer always installed;
`MainMenuController` stops creating an `NSStatusItem` and remains the builder
and `@objc` target for those rows (`buildAppItems` is already the single seam).
`AppController.applyCompactMode` and `MainMenuController.setVisible` go away.

Rename `CompactMenuBarController` → `VeeHomeItemController` (and its test file);
the old name describes a mode that no longer exists. `installFooter`/
`removeFooter` collapse into unconditional setup, and `deactivate()` is deleted
— the item never goes away.

With zero folded plugins the item shows exactly what `MainMenuController` shows
today, so a user who never opens the new control sees no change.

### 5. `StatusItemController` needs the plugin's ID

It currently knows `pluginName` and `autosaveName`
(`"com.vee.plugin.\(id)"`, `PluginCoordinator.swift:123`) but not the ID, and
placement is keyed by ID. Add a `pluginID: String` init parameter rather than
parsing it back out of `autosaveName`.

### 6. Position memory is keyed by plugin, not by placement

`autosaveName` already restores a standalone item's slot. Placement changes
never clear it, so `own → folded → own` returns the item to the same slot.
Folded rows keep the shared menu's insertion order (`rowItems`); user-ordered
folded rows are out of scope (Open Questions).

### 7. Migration reads the old key, never writes it

Absent a per-plugin override, placement resolves to the default, and the
default is derived from `compactMenuBar` (`true` → `.foldedDefault`, `false` →
`.own`). The old key keeps being decoded, so a downgrade or a synced
preferences domain still makes sense. Only departures from the default are
stored per plugin — the same pattern `hotkeyPresentation` already uses
(`AppPreferences.swift:118`), keeping the map empty for most installs and
giving `clearAllState` less to undo.

### 8. Reachability moves to Plugin Manager

A hidden plugin's dropdown is the only place "Open in Window", settings, debug,
reveal and edit live today. Plugin Manager rows already list every plugin and
own enable/disable; they gain the same actions, driven by the same closures
`StatusItemController` is constructed with (`onRefresh`/`onSettings`/
`onReveal`/`onEdit`/`onDebug`) — one new call site, no new plumbing.

## Risks / Trade-offs

- [A hidden plugin is invisible when it fails] → exactly why
  `plugin-attention-promotion` is the immediate follow-up. Until it lands,
  `hidden` is opt-in per plugin and the Plugin Manager row shows plugin health.
- [Merging the two Vee items touches the launch path] → behaviour with zero
  folded plugins is identical to today's non-compact item, and the app-controls
  rows keep coming from the one existing seam; the merge deletes wiring rather
  than adding it.
- [Three placements is more UI than one toggle] → the default-placement control
  keeps the one-toggle experience; the per-plugin control is an override, not a
  decision every user must make.
- [`hidden` can strand a user who does not know about windows or hotkeys] →
  mitigated by offering those surfaces at the moment of hiding (task 5.3) and
  by Plugin Manager carrying the actions.

## Open Questions

- Folded rows have no user-controlled order (insertion order today). Follow-up
  if users ask; not gating.
- A user who hides a plugin "for the widget" gets no card unless its author
  declared `.both`/`.widget`. Out of scope — recorded so the placement UI does
  not imply otherwise.
