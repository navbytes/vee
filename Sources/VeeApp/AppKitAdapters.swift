#if canImport(AppKit)
import AppKit
import VeeProtocol
import VeeServices

/// Thin AppKit implementations of the launcher seams. These COMPILE against
/// AppKit but contain NO branching/business logic — they only translate the
/// coordinator's view models into native widgets and forward callbacks. All
/// decision-making lives in the (tested) `AppCoordinator`; these adapters are
/// verified by manual desktop testing (window appearance, menubar, hotkey fire,
/// TCC prompts), not by the headless unit suite.
///
/// Everything here is `@MainActor` because AppKit demands the main thread; the
/// `vee` target builds in Swift 5 language mode so the actor hop is implicit.

// MARK: - Launcher window (NSPanel + a simple NSView host)

@MainActor
public final class AppKitLauncherWindow: NSObject, @MainActor LauncherWindowPresenting {
    private let panel: NSPanel
    private let label: NSTextField

    public override init() {
        // A non-activating floating panel is the standard launcher shell.
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // A placeholder content view; the real renderer (NSTableView/NSStackView
        // tree) replaces this. Kept inert here so there's no logic to test.
        label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(label)
        panel.contentView = content
        super.init()

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            label.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
        ])
    }

    /// Translate the projected surface into the placeholder view. A production
    /// renderer would build a table/detail tree here; this only forwards a
    /// human-readable summary so the adapter stays logic-free.
    public func setRootViewModel(_ root: RootViewModel?) {
        label.stringValue = AppKitLauncherWindow.summary(of: root)
    }

    public func showLauncher() {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    public func hideLauncher() {
        panel.orderOut(nil)
    }

    /// A flat string summary of the surface — pure translation, no decisions.
    private static func summary(of root: RootViewModel?) -> String {
        guard let root else { return "" }
        switch root {
        case .list(let list): return list.items.map(\.title).joined(separator: "\n")
        case .detail(let d): return d.title ?? d.markdown
        case .empty(let e): return e.title ?? ""
        case .none: return ""
        }
    }
}

// MARK: - Menubar (NSStatusItem)

@MainActor
public final class AppKitMenuBar: @MainActor MenuBarPresenting {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    public init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
    }

    public func setMenuBarTitle(_ title: String?) {
        statusItem.button?.title = title ?? ""
    }

    public func setMenuBarItems(_ items: [MenuBarItemViewModel]) {
        menu.removeAllItems()
        for item in items {
            let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            menuItem.representedObject = item.actionId
            menu.addItem(menuItem)
        }
    }
}
#endif
