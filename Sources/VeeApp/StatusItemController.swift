import AppKit
import VeeCore

/// Owns a single `NSStatusItem` in the system menu bar. Stage 0 shows a static
/// icon and a minimal menu; later stages drive the title and menu from parsed
/// plugin output.
@MainActor
public final class StatusItemController {
    private let statusItem: NSStatusItem
    private let log = VeeLog.make("status-item")

    public init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "v.circle", accessibilityDescription: "Vee")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
        }

        statusItem.menu = makeMenu()
        log.debug("status item installed")
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Vee", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Vee",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        return menu
    }
}
