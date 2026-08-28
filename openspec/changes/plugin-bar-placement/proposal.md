# Proposal: plugin-bar-placement

## Why

Menu-bar crowding has one knob today: `AppPreferences.compactMenuBar`, a single
global boolean. Either every plugin gets its own `NSStatusItem`, or every plugin
folds into rows of one shared Vee item (issues #45, #71). All-or-nothing is the
smaller problem. The larger one is that both settings assume the menu bar is
where a plugin is *read* — but a plugin the user consumes on the widget, in a
detached window, or through the `<vee.filter>` hotkey panel wants no bar
presence at all, and folding it into the shared menu only moves the clutter one
click deeper.

So the real choice is per plugin, and it has three answers, not two. The
roadmap's Focus-filter item is blocked on the same two missing pieces — "a
plugin-grouping model and a lightweight status-item hide" (`docs/design/
roadmap.md`) — which this change supplies.

## What Changes

- **Per-plugin placement**, three values: `own` (its own status item — today's
  default), `folded` (a row in the shared Vee item), `hidden` (no menu-bar
  presence at all). Applies live, with no relaunch, exactly as the compact
  toggle does today.
- **Placement is the user's, not the author's.** No plugin header claims a bar
  slot; every author believes their plugin is the important one. `<vee.surface>`
  keeps deciding whether a plugin has a menu surface *at all* — placement
  decides only where that surface appears.
- **`compactMenuBar` becomes the default placement** for plugins with no
  override, and keeps decoding: `true` → default `folded`, `false` → default
  `own`. No stored preference changes meaning on upgrade, and flipping the
  default never erases per-plugin overrides.
- **`hidden` is presentation-only.** The plugin's `StatusItemController` stays
  alive and its menu-mode run and schedule are untouched, so detached windows,
  the search panel, the widget snapshot, and staleness marking keep working.
  This is deliberately *not* the `<vee.surface>widget` path, which nils the
  controller (`PluginCoordinator.swift:111`) and skips the menu-mode run
  entirely (`:223`) — taking with it the very surfaces the user hid the plugin
  in favour of.
- **One Vee item.** `MainMenuController`'s own item and
  `CompactMenuBarController`'s shared item merge into a single always-present
  home item hosting folded rows plus the app-controls footer, replacing the
  mutually-exclusive show/hide wiring in `AppController.applyCompactMode`.
- **Reachability without a bar item.** Plugin Manager rows carry the per-plugin
  actions the dropdown carries (refresh, open in window, settings, debug,
  reveal, edit), so a `hidden` plugin is never stranded.
- **Hiding offers what replaces it.** Choosing `hidden` surfaces the
  alternatives at that moment — open a window, bind a hotkey — rather than
  leaving the plugin nowhere and the user to rediscover those features.

## Behaviour contract

The `openspec` CLI is not installed in this environment, so this change
declares `skip_specs: true` and carries no `specs/` deltas — nothing would
validate, sync, or archive them. `design.md` and the acceptance checks in
`tasks.md` are the authority instead.

One existing main spec is contradicted by this change and is amended as part of
it (task 6.2): `openspec/specs/detached-plugin-windows/spec.md` guarantees
"Open in Window" is offered "in each plugin's dropdown … for every plugin". A
hidden plugin has no dropdown, so the guarantee is restated as reachability —
the action stays available for every plugin, from a route that survives the
plugin having no menu-bar presence.

## Impact

- `Sources/VeePreferences/AppPreferences.swift` — per-plugin placement store
  alongside `disabledIDs`/hotkey overrides; `clearAllState(id:)` extended so a
  deleted plugin's placement is collected with the rest of its state.
- `Sources/VeeApp/StatusItemController.swift` — `reconcileMode()` generalized
  from a boolean to a placement; a third "no bar surface" case in
  `applyPresentation`/`applyMenu`; `repaintCurrentSurface()` unchanged.
- `Sources/VeeApp/CompactMenuBarController.swift`,
  `Sources/VeeApp/MainMenuController.swift`, `Sources/VeeApp/AppController.swift`
  — the two Vee items merged into one always-present home item.
- `Sources/VeeUI/GeneralSettingsView.swift` — the Menu Bar section becomes a
  default-placement choice; `Sources/VeeUI` plugin rows gain the per-plugin
  placement control and the actions that keep a hidden plugin reachable.
- Docs site: the menu-bar section, and a note distinguishing user placement
  from author-declared `<vee.surface>`.
- No `LineParams`/`MenuAccessory`/`WidgetNode`/`WidgetCard` change, so no
  `WidgetParity` or surface-parity ledger work.
- `plugin-attention-promotion` builds directly on this change's placement value
  and should land after it.
