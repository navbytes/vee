import Foundation

/// The user-intent surface a launcher window forwards keystrokes/clicks into.
///
/// This is deliberately the *exact* subset of `AppCoordinator` the GUI needs to
/// drive, expressed as a protocol so the view layer holds no concrete coordinator
/// type and remains a thin renderer. The coordinator owns ALL behavior behind
/// these calls (filtering, selection rules, action dispatch); the window only
/// translates a user gesture into one of them. `AppCoordinator` conforms.
public protocol LauncherIntentHandling: AnyObject {
    /// The search text changed; the coordinator filters natively (no IPC on a keystroke).
    func setQuery(_ query: String)
    /// The user picked a row; select it by id (coordinator clamps/validates).
    func select(id: String)
    /// Move the selection by `delta` rows (↑/↓); coordinator clamps to the list.
    func moveSelection(by delta: Int)
    /// Invoke an action id on the current selection (Return / action shortcut).
    func invoke(action actionId: String)
}

/// The AppKit launcher-window seam. The coordinator hands it projected view
/// models and asks it to show/hide; the thin `NSPanel`/`NSView` adapter
/// (`AppKitLauncherWindow`) translates these to native views with NO branching
/// logic of its own. Defining it as a protocol keeps all decision-making in the
/// (tested) coordinator and lets the suite assert against a spy.
public protocol LauncherWindowPresenting: AnyObject {
    /// Replace the rendered view-model tree (nil = nothing to show yet).
    func setRootViewModel(_ root: RootViewModel?)
    /// Show the launcher panel and focus the search field.
    func showLauncher()
    /// Hide the launcher panel.
    func hideLauncher()
    /// Give the window the intent sink it forwards user gestures to. The
    /// coordinator calls this when it becomes the window's owner, so the search
    /// field / table / key handling can call back without the view ever holding a
    /// concrete coordinator type. Optional: a default no-op keeps headless spies
    /// (which never originate intent) source-compatible.
    func attach(intentHandler: LauncherIntentHandling)
}

public extension LauncherWindowPresenting {
    /// Default no-op: spies and non-interactive presenters ignore intent wiring.
    func attach(intentHandler: LauncherIntentHandling) {}
}

/// The menubar seam (`NSStatusItem`). The coordinator sets a title + items; the
/// thin adapter (`AppKitMenuBar`) forwards them. No logic below the seam.
public protocol MenuBarPresenting: AnyObject {
    func setMenuBarTitle(_ title: String?)
    func setMenuBarItems(_ items: [MenuBarItemViewModel])
}
