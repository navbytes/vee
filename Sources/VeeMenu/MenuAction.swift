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
/// One instance is retained per status item (menu-item `target` is weak, so the
/// owner must keep this alive).
@MainActor
public final class MenuActionTarget: NSObject {
    private weak var handler: MenuActionHandling?

    public init(handler: MenuActionHandling) {
        self.handler = handler
    }

    @objc func selectItem(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? MenuItemBox else { return }
        handler?.perform(box.item)
    }

    var action: Selector { #selector(selectItem(_:)) }
}
