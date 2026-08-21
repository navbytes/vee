## 1. Split presentation out of the search panel

Groundwork. Nothing user-visible changes here, and the acceptance bar for the
whole section is that every existing search-panel test passes untouched.

- [x] 1.1 Separate the panel's *content* (the SwiftUI view + view model) from its
      *presentation* (`KeyablePanel`, `.popUpMenu` level, transient collection
      behavior, mouse anchoring, the Escape/outside-click monitors,
      `FrontmostAppRestorer`), so a second presentation can host the same
      content.
- [x] 1.2 Keep the transient path constructing exactly what it constructs today —
      branch rather than generalize. Confirm dismissal, focus restoration, and
      keyboard navigation are byte-for-byte unchanged in behavior.
- [x] 1.3 Let `MenuSearchViewModel` accept a refreshed entry set, preserving the
      live query and re-deriving the selection. The transient path must keep its
      frozen-at-open snapshot and never call it.

## 2. Rich rows in the shared row view

The real remaining rendering work — see design.md *Decision 7*.

- [x] 2.1 Apply `color=` and ANSI runs to row text as an `AttributedString`,
      matching what `AttributedTitleFactory` produces for the menu.
- [x] 2.2 Render `progress=` as a SwiftUI capsule gauge, reusing
      `ProgressBarLayout` for geometry so window and menu can't diverge on
      sizing. Honor `accessory=leading`, `color=`, `trackcolor=`,
      `progressw=`/`progressh=`.
- [x] 2.3 Render `sparkline=` and the `pie=`/`donut=`/`stackedbar=` family
      compactly in the row. NOTE: not by hosting `SparklineChartView` /
      `CategoryChartView` as this task first assumed — those are popover
      surfaces that bake in a Liquid Glass card, 14pt padding and a 220pt
      minimum width, i.e. a card several times taller than the row it would sit
      in. The menu bar already splits inline from popover the same way
      (`SparklineMenuItemView` vs `SparklineChartView`); `MenuRowAccessory` is
      the SwiftUI counterpart of the inline half, sharing colors
      (`ChartSegmentColor`) and metrics so the surfaces cannot drift, and a
      click still opens the full popover.
- [x] 2.4 Render `toggle=`/`slider=` live in the row. NOTE: same deviation as
      2.3, plus one of its own — a detached control must adopt values arriving
      from later refreshes, which `PluginControlView` deliberately does not do
      (it seeds `@State` once, correct for a popover that lives seconds). The
      inline control adopts on change and suppresses adoption mid-drag.
- [x] 2.5 Resolve the keyboard/mouse focus split for control rows per design.md
      *Risks*: selection addresses the row; controls are mouse-first; Return on a
      control row activates it the way the panel does today.
- [x] 2.6 Confirm the flattener's existing handling carries over unchanged:
      `⌥` alternates render as ordinary peer rows, `key=` equivalents are not
      bound, and `dropdown=false` rows stay omitted.

## 3. The window presentation

- [x] 3.1 Add a window presentation hosting the same content view: titled,
      closable, resizable, movable, with an explicit initial content size.
- [x] 3.2 Add a manager keyed by plugin, modeled on `DebugWindowManager`: one
      window per plugin, focus-not-duplicate on re-invoke, close-observer tokens
      owned in manager state, cascade placement.
- [x] 3.3 Add the pin control, switching `level` and `collectionBehavior`
      together as a pair per design.md *Decision 3*. Default pinned.
- [x] 3.4 Remember pin state per plugin for the session, so a window reopens the
      way it was last left.

## 4. Liveness and lifecycle

- [x] 4.1 Feed open windows from `StatusItemController.render` — the single place
      fresh output reaches the UI. Re-flatten and replace wholesale.
- [x] 4.2 Preserve an active query across a refresh: new output, same filter.
- [x] 4.3 Mark a plugin's window stale from `PluginCoordinator.teardown`, so a
      disabled or removed plugin stops implying its window is live.
- [x] 4.4 Mark stale on the error/timeout path, keeping the last successful
      output on screen; clear the flag when good output returns.
- [x] 4.5 Add the stale indication to the window's chrome — visible, and leaving
      the last output on screen.

## 5. Ways in and ways back

- [x] 5.1 Add the "Open in Window" row to the plugin dropdown's footer in
      `StatusItemController`, beside Refresh / Settings / Debug.
- [x] 5.2 Add the "keep open" control to the transient panel, promoting it to a
      window for the same plugin and closing the panel so nothing shows twice.
- [x] 5.3 Add the "Detached Windows" submenu to
      `MainMenuController.buildAppItems` — the shared seam, so compact mode's
      folded footer gets it too. One row per open window; selecting brings it to
      the front; hidden entirely when nothing is open.
- [x] 5.4 Remove a window from the list when it closes by any route, including
      the title-bar control, so re-invoking opens a fresh window.

## 6. Hotkey presentation choice (design.md *Decision 5*)

- [x] 6.1 Add the per-plugin preference for which presentation `<vee.shortcut>`
      opens, defaulting to the transient panel so existing plugins are
      unaffected.
- [x] 6.2 Switch on it at the single registration site in
      `PluginCoordinator.registerHotKey()` — one closure. Everything else in the
      hotkey stack (`EffectiveHotkey`, `HotkeyStatus`, disable/rebind, collision
      reporting, trust disclosure) must remain untouched.
- [x] 6.3 Add the picker to the per-plugin Settings form, shown only when the
      plugin declares a hotkey, re-registering live on change the way
      `applyHotkey` already does.
- [x] 6.4 Confirm the window setting focuses an already-open window rather than
      opening a second, giving the hotkey its retrieval role.

## 7. Tests

- [x] 7.1 Regression first: the existing search-panel and `MenuSearchViewModel`
      tests pass with no edits. If one needs changing, the presentation split
      leaked into the transient path.
- [x] 7.2 View-model tests for refreshed entries: query preserved, selection
      re-derived sensibly, and the transient path never refreshed.
- [x] 7.3 Manager unit tests: one window per plugin, re-invoke focuses rather
      than duplicates, close evicts the entry and unregisters its observer,
      several plugins tracked independently.
- [x] 7.4 Liveness tests: a fresh parse reaches an open window; teardown marks
      stale; recovery clears the flag.
- [x] 7.5 Row tests: accessory precedence (`MenuRowAccessoryTests`) and the
      shared gauge defaults. The flattener half needed no new tests —
      `MenuFlattenerTests.testAlternateItemFlattenedAsSearchableActivatableRow`
      and `testFlattenEntriesDropdownFalseInvisibleButStillDescends` already
      pin alternates-as-peer-rows and `dropdown=false` omission, and the window
      inherits both by reusing the flattener.
- [x] 7.6 Hotkey tests: default resolves to the transient panel; the window
      setting resolves to the window; disable and rebind behave identically under
      both.
- [x] 7.7 Pin tests: level and collection behavior always change as a pair; pin
      state survives close-and-reopen within the session.
- [x] 7.8 Follow the existing test seams — construct no real `NSStatusItem` or
      `NSWindow` where an `attachesStatusItem`-style injection point can avoid it
      (see `MainMenuController`, `CompactMenuBarController`).

## 8. Accessibility and verification

- [x] 8.1 VoiceOver: every row reachable and labeled; charts and gauges announce
      their values as they do in the popovers; the pin and "keep open" controls
      are their own elements with clear labels. (Labels implemented and reviewed
      statically — gauges announce a percentage, sparklines their latest value
      and range, charts reuse `ChartParams.accessibilitySummary()`, and both
      buttons are separate elements with label + value. Confirming by ear is
      part of 8.2.)
- [ ] 8.2 Verify on-device: a window stays live across refreshes; a pinned window
      remains visible over a full-screen app and across a Space switch; an
      unpinned window is reachable from Mission Control and from the Detached
      Windows list; the hotkey opens and then focuses; the transient panel still
      behaves exactly as before.
      NOT DONE — needs a human at the screen. `xcodebuild -scheme Vee` succeeds
      and the full suite is green, but every item here is a behavioral check
      against the window server (Spaces, full-screen, Mission Control) or the
      menu bar, which cannot be observed from a headless session. Launching the
      debug build was also declined deliberately: it would add a second Vee
      status item beside any running instance, with both writing
      `widget-snapshot.json`.
- [x] 8.3 Run `swift test` and the lint workflow; no new warnings.

## 9. Documentation

- [x] 9.1 Document the window presentation in
      `docs/_content/plugin-authoring.md` — what it renders, that it carries the
      panel's search, and the fidelity boundary (⌥ alternates and `key=` are
      menu-only).
- [x] 9.2 Document the hotkey presentation choice in the same `<vee.shortcut>`
      section, noting the default is unchanged.
- [x] 9.3 Regenerate the guide with `docs/scripts/build_guide.py` and confirm
      `--check` passes, per CONTRIBUTING.
- [x] 9.4 Add a CHANGELOG entry.
- [x] 9.5 Update `ARCHITECTURE.md` and `docs/_content/roadmap.md` — record that
      the search panel now has two presentations, so the next person does not
      re-propose a separate window renderer.
