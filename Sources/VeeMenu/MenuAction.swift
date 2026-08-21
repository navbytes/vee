import AppKit
import VeePluginFormat

/// Handles activation of a menu item (open href, run shell, refresh, …). The app
/// provides a concrete implementation; `VeeMenu` stays UI-only.
@MainActor
public protocol MenuActionHandling: AnyObject {
    func perform(_ item: MenuItem)

    /// Re-invokes a `toggle=`/`slider=` row's command with a settled value,
    /// without going through the control's popover.
    ///
    /// `perform` opens the popover for a control row, which is right for a click
    /// in the menu bar but wrong for a detached window that draws the control
    /// inline and already has the value. Both paths end in the same
    /// re-invocation, so this is the shared half rather than a second one.
    func commitControl(_ item: MenuItem, value: Double)
}

public extension MenuActionHandling {
    /// Default no-op so a handler that renders no controls (tests, the CLI)
    /// need not implement it.
    func commitControl(_ item: MenuItem, value: Double) {}
}

/// Reference wrapper so a value-type `MenuItem` can live in `representedObject`.
final class MenuItemBox: NSObject {
    let item: MenuItem
    init(_ item: MenuItem) { self.item = item }
}

/// `@objc` target that bridges menu-item selection to a `MenuActionHandling`.
/// `NSMenuItem.target` is weak and the app creates the handler
/// (`AppActionDispatcher`) inline, so the target **owns its handler strongly** —
/// otherwise the handler would deallocate right after init and every click would
/// call a nil handler (a silent no-op). No retain cycle: the handler never
/// references the target back. The target itself is kept alive by its owner
/// (`StatusItemController`).
@MainActor
public final class MenuActionTarget: NSObject {
    private let handler: MenuActionHandling

    public init(handler: MenuActionHandling) {
        self.handler = handler
    }

    @objc func selectItem(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? MenuItemBox else { return }
        handler.perform(box.item)
    }

    var action: Selector { #selector(selectItem(_:)) }
}
