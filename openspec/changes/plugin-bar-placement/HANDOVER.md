# Handover: plugin-bar-placement

Written in a Linux cloud session with **no Swift toolchain** (`swift`,
`swiftc` and `swiftlint` are all absent), against a package that targets
macOS 26 + AppKit. So:

**Nothing in this change has been compiled, tested, or seen running.** Every
line was written and reviewed by eye. Treat it as a complete draft that needs a
compiler pointed at it, not as working code.

First thing on a Mac:

```sh
swift build && swift test && swiftlint lint --strict
```

## What is implemented

Tasks 1.x, 2.x, 3.2, 3.3, 4.x, 5.1 and 5.2 in `tasks.md`, i.e. the whole
change except the rename (3.1), the hide-time offer of alternative surfaces
(5.3), and the docs-site page (6.1).

**New:**
- `Sources/VeePreferences/BarPlacement.swift` — `own` / `folded(group:)` /
  `hidden`, with `encoded`/`init?(encoded:)`.
- `Tests/VeePreferencesTests/BarPlacementTests.swift` — encoding round trips,
  override-vs-default, the legacy migration, GC.

**Changed:**
- `AppPreferences` — `defaultPlacement` (falling back to the legacy
  `compactMenuBar` boolean), `placement(_:)` / `placementOverride(_:)` /
  `setPlacement(_:id:)` / `placementIDs()`; `clearAllState` collects placement;
  `compactMenuBarDidChangeNotification` → `barPlacementDidChangeNotification`.
- `StatusItemController` — `pluginID:` init param (optional, so ephemeral
  deep-link items follow the default); `isCompact: Bool` → `placement:
  BarPlacement`; `reconcileMode()` → `reconcilePlacement()` +
  `detachBarSurface()`; `isFolded` drives the key-equivalent stripping.
- `CompactMenuBarController` — permanent item, footer installed once,
  `removeFooter()` deleted.
- `MainMenuController` — owns no status item; `setVisible`/`isVisible`/
  `remove()` deleted.
- `AppController` — `applyCompactMode` and its observer deleted, footer
  installed unconditionally at launch; `placementIDs()` added to
  `reconcileDiskState`'s candidate set; Manager model wired with placement,
  refresh and open-window.
- `PluginCoordinator` — passes `pluginID`; new `openWindow()`.
- `PluginManagerView` — row carries its placement override; overflow menu gains
  Refresh, Open in Window, and a "Menu Bar" submenu.
- `GeneralSettingsView` — `compactMenuBar` → `foldPluginsByDefault`, writing
  `defaultPlacement`.
- Tests updated: `CompactMenuBarControllerTests` (+4 new placement tests),
  `MainMenuControllerTests`, `GeneralSettingsModelTests` (rewritten).

## Where the compiler is most likely to complain

Ranked by my own confidence, least confident first:

1. **`PluginManagerView`'s `switch` expressions** (`defaultPlacementLabel`,
   `placementSymbol`) — implicit-return switch expressions in computed
   properties. Correct Swift 5.9+, but the file's other properties do not use
   the form, so it is the least idiomatic thing I added here.
2. **`placementRow(_:_:)` returning `some View`** with a `let` before `return`
   and an `if/else` inside the `Button` label. Should be fine; it is the only
   new view builder.
3. **`BarPlacement.init(encoded:)`'s `encoded[..<separator] == "folded"`** —
   `Substring` vs a string literal. The literal should infer as `Substring`; if
   it does not, wrap it: `String(encoded[..<separator]) == "folded"`.
4. **The new tests' main-queue drain** — they copy the pattern
   `testRedundantModeChangeNotificationIsIdempotent` already uses (post, then
   `DispatchQueue.main.async` a marker and wait). If placement notifications
   turn out to be delivered synchronously, the waits are harmless but the
   assertions may need reordering.
5. **SF Symbol names** — `menubar.rectangle`, `rectangle.stack`, `eye.slash`,
   `macwindow`. Unverified; substitute freely.

I did **not** find a way to check any of the above without a toolchain.

## What is deliberately left

- **3.1, the rename** `CompactMenuBarController` → `VeeHomeItemController`.
  The name now describes a mode that no longer exists. Left undone on purpose:
  a cross-file rename is trivially safe with a compiler and error-prone
  without one. Worth doing first, before the diff grows. The internal
  vocabulary (`compactEntry`, `setCompactTitle`, `compactController`,
  `isCompactDimmed`) should follow it.
- **5.3, offering the alternative surfaces when a user hides a plugin.** This
  is the UX half of why `hidden` exists — a user hides a plugin *because* they
  read it on the widget, in a window, or through its hotkey — and it wants
  someone who can see the sheet they are building. The placement control works
  without it; the feature is less discoverable.
- **6.1, the docs-site page.** Compact mode turns out never to have been
  documented on the site at all, so this is new prose rather than an edit, and
  it reads better written against the shipped UI.
- **Edit-in-editor on the Manager row.** Every other per-plugin action is
  there; this one needed a second new `PluginCoordinator` method and Reveal in
  Finder already covers the case.

## Judgement calls worth a second opinion

- **`hidden` keeps the `StatusItemController` alive.** It is the load-bearing
  decision of the change: that controller drives `DetachedPluginWindows`,
  `MenuSearchPanel` and the widget scrape, so reusing the `<vee.surface>widget`
  path (which nils the controller) would silently kill the surfaces a hiding
  user is relying on. `design.md` §3 has the detail.
- **A placement equal to the current default is still stored** as an override.
  "Pinned because I said so" and "pinned because the default is" differ the
  moment the default changes. It does mean the map is not minimal.
- **The default placement lives in a new key**, not by writing the old
  `compactMenuBar` boolean, so `hidden` could become a default later without
  silent coercion. The old key is still read, never written.
