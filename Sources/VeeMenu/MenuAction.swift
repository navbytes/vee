import AppKit
import VeePluginFormat

/// Handles activation of a menu item (open href, run shell, refresh, …). The app
/// provides a concrete implementation; `VeeMenu` stays UI-only.
@MainActor
public protocol MenuActionHandling: AnyObject {
    func perform(_ item: MenuItem)
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
