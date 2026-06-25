import Foundation

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
}

/// The menubar seam (`NSStatusItem`). The coordinator sets a title + items; the
/// thin adapter (`AppKitMenuBar`) forwards them. No logic below the seam.
public protocol MenuBarPresenting: AnyObject {
    func setMenuBarTitle(_ title: String?)
    func setMenuBarItems(_ items: [MenuBarItemViewModel])
}
