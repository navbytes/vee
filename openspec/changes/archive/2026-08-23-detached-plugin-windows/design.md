## Context

See [`proposal.md`](proposal.md) for motivation and
[`specs/`](specs/detached-plugin-windows/spec.md) for the behavior contract. What
follows is the state of the codebase that shapes the approach.

**Vee runs as an accessory app.** `Sources/vee/Vee.swift:34` sets `.accessory`
(`LSUIElement`). No Dock icon, no ⌘-Tab entry. This is not cosmetic: it removes
two of the three ways macOS normally lets you return to a window you covered up,
which makes window level a retrieval problem rather than a matter of taste. See
*Decision 3*.

**The search panel is already most of the window.** `VeeApp/MenuSearchPanel.swift`
+ `MenuSearchView` + `MenuSearchViewModel`, with `VeeSearch` behind them, already:

- render a plugin's **entire** menu structure in SwiftUI — `MenuSearch.search("")`
  returns every entry, so the idle panel is the whole tree, flattened, with
  section headers and separators intact (`5d5ef22`);
- draw rows with SF Symbol and base64 icons through the same `SymbolImageFactory`
  `MenuBuilder` uses, plus `checked=` state and ancestor breadcrumbs;
- dispatch activations through the real handler —
  `activate: { self?.handler.perform(row.item) }` — so `href=`, `shell=`,
  `shortcut=`, `refresh=`, `webview=` and the control popovers all fire with no
  parallel action model;
- solve the two accessory-app problems this feature would otherwise hit:
  `KeyablePanel` overrides `canBecomeKey` because a borderless panel in a
  non-active app cannot otherwise take keystrokes, and `FrontmostAppRestorer`
  hands focus back so a clipboard plugin's simulated ⌘V lands in the app the user
  came from rather than in Vee;
- read from `StatusItemController.lastBody`, which is already the latest parse.

It is transient only because nothing has needed it to be otherwise:
`.popUpMenu` level, `[.transient, .ignoresCycle]`, borderless,
`isMovable = false`, fixed 440×380, dismissed by Escape, outside click, or row
activation. Its model documents the corresponding simplification — *"Entries are
frozen at open (the plugin may re-run on its interval while the panel is up)"*.

**Dropdowns are `NSMenu`, and that does not transfer.**
`VeeMenu/MenuBuilder.build(_:target:)` returns an `NSMenu`; everything hanging off
it is `NSMenuItem`-shaped (`AttributedTitleFactory`, the three custom
`NSMenuItem.view` renderers, `NSMenuItem.sectionHeader`, `isAlternate`,
`keyEquivalent`). An `NSMenu` cannot be hosted in an `NSWindow`. This is why the
window is built from the panel rather than from the menu.

**Two window managers already establish the pattern.** `DebugWindowManager`
(`VeeUI/PluginDebugWindow.swift`) is keyed by plugin, keeps its window live while
the plugin re-runs, focuses rather than duplicates on re-invoke, and owns its
close-observer tokens in manager state rather than in the observer closure — a
deliberate strict-concurrency choice, documented there and repeated in
`SettingsWindowManager`.

**Nothing in the repo persists a window.** Zero `setFrameAutosaveName`, zero
`isRestorable`. Session-scoped windows match every other window Vee opens.

**The global-hotkey stack is action-agnostic and already reused twice.**
`GlobalHotKeys.register(_:action:)` takes an arbitrary `() -> Void`.
`HotKeySpec`, `EffectiveHotkey.resolve`, `HotkeyStatus`, the per-plugin
disable/rebind preferences, the collision reporting and the trust disclosure are
all indifferent to what fires. `PluginCoordinator.registerHotKey()` uses it for a
plugin's search panel; `AppController.registerSearchAllHotkey()` uses it at app
level for cross-plugin search.

## Goals / Non-Goals

**Goals**

- One rendering path for a plugin's menu surface, so the panel and the window
  cannot drift on what a row means.
- Preserve the transient panel's behavior exactly. This change adds a
  presentation; it does not alter the one that exists.
- Liveness through the existing single choke point for fresh output, not a second
  subscription mechanism.
- Reuse the established manager patterns rather than inventing parallel ones.

**Non-Goals**

- Pixel parity with `NSMenu`. This surface is a *view* with a declared fidelity
  boundary, following the precedent in
  [`docs/design/terminal-view.md`](../../../docs/design/terminal-view.md), which
  declines parity-chasing as a stated principle.
- Replacing or competing with the WidgetKit surface.
- Any change to the runtime, parser, trust layer, catalog, or widget channel.

## Decisions

### 1. One surface, two presentations — not a second renderer

The search panel and the detached window want to display the same thing: a
plugin's whole menu surface, in SwiftUI, with working actions. The only genuine
differences are lifetime, chrome, and whether the content updates. So the window
is a *presentation* of the existing panel, not a new view built beside it.

```
  MenuSearchView  ── one renderer, gaining the rich row family
       │
       ├─ transient   KeyablePanel · .popUpMenu · frozen entries ·
       │              Esc / outside-click / activate to dismiss
       │              ← unchanged
       │
       └─ window      titled · resizable · movable · floating|normal ·
                      live entries · one per plugin · listed for retrieval
```

What this avoids building: a tree-to-SwiftUI renderer, a second row view, a
second action wiring, a second answer to `canBecomeKey`, and a second focus
restoration path.

What it gains for free: **search inside the window.** For a plugin with a large
tree, that is genuinely useful, and it is what makes *Decision 5* costless.

**Alternative rejected — a separate window renderer over `[MenuNode]`.** The
original shape of this change. It duplicates a renderer that already exists and
creates a permanent drift risk between two views of the same parse.

**Alternative rejected — render into an `NSMenu` shown at a fixed screen point.**
An `NSMenu` in tracking mode runs a modal event loop, blocks the rest of the UI,
and closes on the first outside click. It cannot be left open, which is the whole
request.

### 2. Keep the flattened list; do not add tree navigation

The panel flattens the tree and shows ancestors as breadcrumbs, because that is
the right shape for a finder. It turns out to be the right shape for a *watcher*
too: everything is visible at once, with no descending into submenus to find the
value you opened the window to see. A window you are monitoring should not
require clicks to reveal its contents.

So nested navigation is not built. This is a simplification, not a compromise.

**Trade-off:** a plugin with a very large tree produces a long list. It scrolls,
and it has a search field — which the dropdown does not.

### 3. `.floating` by default, user-switchable, with `collectionBehavior` moved as a pair

Because Vee is an accessory app, a covered unpinned window has no Dock icon to
click and no App Exposé route back — App Exposé is scoped to the frontmost app,
so if the window is behind Safari then Safari is frontmost and the gesture shows
Safari's windows. That circularity is why `.floating` is the default and why
*Decision 6* is not optional.

Level and collection behavior always change together:

| pinned | level | collectionBehavior | rationale |
| --- | --- | --- | --- |
| yes | `.floating` | `[.canJoinAllSpaces, .fullScreenAuxiliary]` | the case that justifies floating is watching a value while working elsewhere — which includes working full-screen and on another Space. Default `.managed` hides the window in exactly that case. |
| no | `.normal` | `.managed` | ordinary window: Mission Control reaches it, Spaces treat it normally. |

`NSWindow.level` is settable at runtime, so the control is a toggle rather than a
re-creation.

**Alternative rejected — a global preference.** Wrong granularity: a 1-second CPU
sparkline wants pinning and a large share chart wants to be out of the way.

**Alternative rejected — a `<vee.*>` declaration.** Wrong owner. Screen layout
belongs to the user, not the plugin author.

**Alternative rejected — a desktop/wallpaper-level layer.** That placement is
what WidgetKit already provides, and reaching it means a private window level or
fighting Stage Manager and Spaces.

### 4. Liveness in the window only, fed from `StatusItemController.render`

`render` is the one place a fresh parse reaches the UI, so it is the one place
windows can be fed. Anywhere else would create a second path that could disagree
with the menu about what a plugin currently says.

The update is a whole-tree replacement: re-flatten the new body and hand the
window the new entries. Because a window tracks a *plugin*, there is nothing to
re-resolve, nothing to match, and no way to bind to the wrong row.

> This is the design's largest simplification over the per-row detach explored on
> `origin/claude/pie-donut-stacked-bar-charts-g713rl`. That version keyed windows
> by `MenuItemPath = [Int]` — a positional address re-resolved on every refresh,
> with an acknowledged failure mode where a plugin reordering its rows silently
> rebound a window to a different row. For a detached slider that meant a
> mis-resolved row could run the wrong command. Keying by plugin deletes the
> problem: a plugin's identity is its filename, which does not drift.

**The transient panel keeps its frozen snapshot.** Its model's existing comment
stays true. Live-updating a list while the user is typing a query and moving a
keyboard selection through it would reorder rows under the cursor — the panel is
open for seconds and does not need it. This split preserves today's behavior
exactly and confines the new mechanism to the presentation that asked for it.

Staleness is the complement: `PluginCoordinator.teardown` marks a plugin's window
stale when the plugin goes away, and the error path leaves the last good output on
screen with the flag set. A frozen reading that looks live is worse than one that
admits it is frozen.

### 5. The plugin's hotkey chooses a presentation

The hotkey stack costs one closure to reuse. The only question was where a second
binding would come from — and merging the surfaces answers it: there is no second
thing to bind. `<vee.shortcut>` keeps its single declaration and single binding,
and the plugin's Settings chooses which presentation it opens. The transient panel
stays the default, so every plugin that already declares a hotkey is unaffected.

Reused for free: the disable/rebind UI, `EffectiveHotkey`'s precedence rules,
`HotkeyStatus` reporting, the "already claimed system-wide" collision error
surfaced in the Plugin Manager, and the trust sheet's disclosure that the plugin
grabs a system-wide key.

When set to *window*, the hotkey calls the same entry point the menu row calls, so
pressing it with the window already open focuses it — making the hotkey a
per-plugin retrieval path, and the only one that never goes through the menu bar.

**This choice now costs the user nothing**, which is what changed: because both
presentations are the same surface, the window carries the search field too. An
earlier revision of this design recorded "you give up the search panel for that
plugin" as an accepted trade-off. Merging the surfaces removed the trade-off
rather than accepting it.

**Alternative rejected — a second `<vee.window.shortcut>` tag.** It duplicates
every layer above: a second header field, a second pair of preference keys, a
second status, a second Settings row, a second collision path, plus plugin-format
documentation and three SDK header builders — a large surface for one binding.

**Alternative rejected — a per-plugin hotkey table keyed by action.** The right
shape *if* a third hotkey action ever appears, but it only becomes useful
alongside a second declaration, so it buys nothing today. Recorded as the upgrade
path.

### 6. A "Detached Windows" submenu built in `MainMenuController.buildAppItems`

`buildAppItems` is the documented single seam both Vee's own status item and
compact mode's folded footer build from, specifically "so the two can never
duplicate or drift out of sync". Adding the submenu there means compact mode gets
it for free.

This is the guaranteed retrieval path — see *Decision 3* for why the system's own
paths are insufficient here. Hidden entirely when nothing is open.

### 7. Fidelity boundary: rich content in, menu mechanics out

Added to what the panel renders today: `progress=` gauges, `sparkline=`, the
`pie=`/`donut=`/`stackedbar=` family, `toggle=` and `slider=` controls, and
per-row `color=`/ANSI styling.

Represented rather than reproduced: an `⌥` alternate is a menu-tracking
affordance — hold a modifier while a menu is open and a row swaps — with no
natural analog in a window. `MenuFlattener.walk` already resolves this, emitting
an alternate as a peer row right after the item it belongs to, explicitly to
close "the silent gap today where an alternate is never shown, searched, or
activatable at all". The window inherits that for free: alternates are visible
and activatable ordinary rows, which is *more* than the dropdown offers without
a modifier held, not less.

Not reproduced: `key=` equivalents, which are scoped to an open menu. They are
simply not bound; the row itself renders and activates normally.

> An earlier revision of this design specified omitting alternate rows entirely.
> That was wrong twice over: it would have made the window show less than the
> panel it shares a renderer with, and it would have required a mode branch in
> the one view — contradicting *Decision 1*. The flattener had already made the
> better call.

This mirrors how `docs/design/terminal-view.md` scoped `vee show`: faithful on
content, explicit about what is *represented rather than reproduced*, and
declining parity as a stated principle rather than an open bug backlog.

### 8. The plugin keeps its menu-bar item

The window is an additional view, not a relocation. The dropdown remains where
Refresh, Settings, Debug, About, trust badges and the last-updated stamp live,
none of which the window renders. Closing the window loses nothing, and
"detached" never means "misplaced".

## Risks / Trade-offs

- **Changing a shipped surface to add a presentation risks regressing it.** The
  transient panel is in daily use and has accumulated real fixes (`0ff20d4`
  search-panel parity, `5d5ef22` structure rendering). → The transient path keeps
  its own construction, its own frozen model, and its own dismissal monitors;
  window mode branches rather than generalizing them. Existing panel tests must
  pass unchanged, and that is the acceptance bar for section 1 of the tasks.

- **Rich rows in a searchable list.** A `toggle=` inside a keyboard-navigable
  filtered list raises focus questions the panel has not had to answer — does
  Return activate the row or the control? → Keyboard selection continues to
  address the row; rich controls are mouse-first, and a row whose only affordance
  is a control is activated the way the panel already activates a control row,
  through the dispatcher.

- **A search field in a monitoring window is unusual furniture.** → It is also the
  thing that makes a large plugin usable in a window, and it is what makes
  *Decision 5* free. If it proves noisy it can collapse, without changing the
  model.

- **More windows in an app already audited for window sprawl** —
  `docs/design/ui-consolidation.md` opens on "four-plus independent top-level
  windows". → These are user-invoked, one per plugin, closable, and listed in one
  place. That doc's target is the *library* surfaces (Preferences, Manager,
  Discover); a live per-plugin view is the same category as the Debug window,
  which it explicitly keeps poppable.

- **A floating window is by definition in the way** — which is what was asked for,
  but it makes the pin control the most-used affordance. → Pin state is remembered
  per plugin for the session, so an unpinned window reopens unpinned.

- **Un-sandboxed rich content on the desktop.** The menu already renders whatever
  a plugin emits; a window renders it for longer and more visibly. → No new
  capability is granted, and the parser's existing guards (non-finite numeric
  params rejected, JSON depth-capped, `ChartParams` segment bound) apply
  unchanged, since the window consumes the same `ParsedOutput`.

## Migration Plan

Additive throughout. No format change, no new header tag, no preference
migration, and no change to any existing surface's behavior — the transient panel
and its hotkey behave exactly as before unless the user opts into the window
presentation. Rollback is removal of the window presentation and its manager plus
the call sites in `StatusItemController`, `MainMenuController`, and
`PluginCoordinator`.

## Open Questions

- **Should the cross-plugin "Search All Plugins" panel gain the same window
  presentation**, giving an all-plugins dashboard? `FlatRow.prefixed(with:)`
  already labels rows by plugin, so the content side is largely solved. Deferred:
  it is additive over this change, needs its own answer for per-plugin liveness
  across many plugins, and changes neither these specs nor the task breakdown.

- **Should the "Detached Windows" list also offer plugins that are not yet open**,
  making it the discovery surface rather than only the retrieval one? Deferred:
  it needs an enumeration over loaded plugins and changes only that submenu's
  contents. Worth revisiting once several windows at once is the normal case.
