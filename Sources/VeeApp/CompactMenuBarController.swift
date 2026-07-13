import AppKit

/// Compact mode (issue #45 — menu-bar crowding): when the user opts in
/// (`AppPreferences.compactMenuBar`), every plugin's `StatusItemController`
/// renders into a row of this ONE shared "Vee" status item instead of
/// getting its own `NSStatusItem`. Each row's title/image mirror what a
/// standalone item would show; its submenu is that plugin's own dropdown,
/// unchanged — `StatusItemController.buildMenu(body:)` is still the single
/// place that's built, reused verbatim for either surface.
///
/// A singleton so any `StatusItemController` (a real plugin or an ephemeral
/// deep-link item) can join or leave without `AppController`/
/// `PluginCoordinator` needing to know compact mode exists at all.
@MainActor
public final class CompactMenuBarController {
    // `public`: referenced as a default argument value in `StatusItemController`'s
    // public initializer (and constructed directly by tests via `@testable
    // import`). Everything else below stays internal — no external module
    // needs to add/remove rows itself.
    public static let shared = CompactMenuBarController()

    private(set) var menu = NSMenu()
    private var statusItem: NSStatusItem?

    /// Skips ever touching `NSStatusBar`: constructing a real `NSStatusItem`
    /// requires a live `NSApplication`, which is unsafe to trigger from a unit
    /// test — it rebinds the MainActor executor process-wide and starves
    /// other suites under CI load (see `WidgetActionRefreshTests`). A test
    /// constructs its own non-attaching instance instead of `.shared`, so the
    /// row bookkeeping below is exercised with zero AppKit application side
    /// effects.
    private let attachesStatusItem: Bool

    init(attachesStatusItem: Bool = true) {
        self.attachesStatusItem = attachesStatusItem
        menu.autoenablesItems = false
    }

    /// Adds a new row to the shared Vee menu (creating the shared status item
    /// on first use) and returns it so the caller can update its own
    /// title/image/submenu directly as its plugin refreshes — the same way it
    /// already updates its own `NSStatusItem` in standalone mode. Never
    /// rebuilds the *other* rows, so a sibling plugin's open submenu is
    /// undisturbed by this one refreshing.
    func addEntry() -> NSMenuItem {
        let item = NSMenuItem()
        menu.addItem(item)
        activateIfNeeded()
        return item
    }

    /// Removes a previously-added row — its plugin stopped, or its controller
    /// switched back to standalone mode. Tears down the shared status item
    /// once the last row is gone (nothing left to show).
    func removeEntry(_ item: NSMenuItem) {
        menu.removeItem(item)
        if menu.items.isEmpty { deactivate() }
    }

    private func activateIfNeeded() {
        guard attachesStatusItem, statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "v.circle.fill", accessibilityDescription: "Vee")
            image?.isTemplate = true
            button.image = image
        }
        // The same `NSMenu` instance for the item's whole lifetime — rows are
        // added/removed/updated in place by `addEntry`/`removeEntry`/the owning
        // `StatusItemController`s, never rebuilt wholesale.
        item.menu = menu
        statusItem = item
    }

    private func deactivate() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }
}
