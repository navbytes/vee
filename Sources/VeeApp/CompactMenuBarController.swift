import AppKit

/// Compact mode (issue #45 — menu-bar crowding): when the user opts in
/// (`AppPreferences.compactMenuBar`), every plugin's `StatusItemController`
/// renders into a row of this ONE shared "Vee" status item instead of
/// getting its own `NSStatusItem`. Each row's title/image mirror what a
/// standalone item would show; its submenu is that plugin's own dropdown,
/// unchanged — `StatusItemController.buildMenu(body:)` is still the single
/// place that's built, reused verbatim for either surface.
///
/// Issue #71 follow-up ("one icon total"): while compact mode is on, this is
/// the ONLY status item — `MainMenuController`'s own item is hidden
/// (`AppController`'s mode-change wiring) and its app-controls rows fold in
/// here as a footer instead (`installFooter`/`removeFooter`), built from the
/// exact same seam (`MainMenuController.buildAppItems`) so the two can never
/// drift out of sync.
///
/// A singleton so any `StatusItemController` (a real plugin or an ephemeral
/// deep-link item) can join or leave without `AppController`/
/// `PluginCoordinator` needing to know compact mode exists at all.
@MainActor
public final class CompactMenuBarController: NSObject, NSMenuDelegate {
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

    /// The shared item's default glyph. Issue #71: while compact mode is on
    /// this is the ONLY Vee icon in the menu bar (`MainMenuController`'s own
    /// item is hidden), so it now uses the same primary glyph that item always
    /// showed — the two are the same icon, not two sitting side by side.
    static let normalSymbolName = "v.circle.fill"
    /// Swapped in once ≥1 row is in an error state — the same symbol
    /// `StatusItemController.renderError` uses for a standalone item's own
    /// error surface, so the roll-up reads as the same "something's wrong"
    /// cue at either level.
    static let errorSymbolName = "exclamationmark.triangle.fill"

    /// Rows currently reporting an error (by identity), so the shared item's
    /// glyph can roll up "≥1 plugin is erroring" without ever inspecting any
    /// row's own submenu. `removeEntry` clears a row's membership too, so a
    /// plugin that's stopped/disabled mid-error can't leave the badge stuck.
    private var erroredEntries: Set<ObjectIdentifier> = []

    /// The symbol name currently applied to the shared item's button. Kept as
    /// a plain, directly testable value — a system-symbol `NSImage` doesn't
    /// retain the name it was created from — rather than only ever being
    /// readable off a real button, which tests never create
    /// (`attachesStatusItem: false`).
    private(set) var currentSymbolName = CompactMenuBarController.normalSymbolName

    /// Plugin rows currently in the shared menu, tracked independently of
    /// `menu.items` now that the app-controls footer (`installFooter`)
    /// permanently occupies the tail of the same menu — `addEntry` needs this
    /// count to keep inserting new rows ABOVE the footer, never appending
    /// past it.
    private var rowItems: [NSMenuItem] = []

    /// The footer's items (a separator + `MainMenuController.buildAppItems`'s
    /// rows), or empty when not installed. Tracked so `installFooter`/
    /// `removeFooter` are idempotent — a repeated live toggle must never
    /// duplicate or double-remove them.
    private var footerItems: [NSMenuItem] = []
    /// The footer's own "Launch Vee at Login" row, kept so `menuNeedsUpdate`
    /// can refresh its checkmark each time the shared menu is about to open —
    /// the same live freshness `MainMenuController` gives its own copy of
    /// this row.
    private weak var footerLoginItem: NSMenuItem?

    init(attachesStatusItem: Bool = true) {
        self.attachesStatusItem = attachesStatusItem
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
    }

    /// Adds a new row to the shared Vee menu (creating the shared status item
    /// on first use) and returns it so the caller can update its own
    /// title/image/submenu directly as its plugin refreshes — the same way it
    /// already updates its own `NSStatusItem` in standalone mode. Never
    /// rebuilds the *other* rows, so a sibling plugin's open submenu is
    /// undisturbed by this one refreshing. Inserted above the app-controls
    /// footer (if installed) — the footer must stay at the tail.
    func addEntry() -> NSMenuItem {
        let item = NSMenuItem()
        menu.insertItem(item, at: rowItems.count)
        rowItems.append(item)
        activateIfNeeded()
        return item
    }

    /// Removes a previously-added row — its plugin stopped, or its controller
    /// switched back to standalone mode. Tears down the shared status item
    /// once the last row is gone AND no footer is installed — the footer
    /// alone (compact mode on, zero plugins) still keeps it alive so
    /// Preferences/Quit/etc. stay reachable.
    func removeEntry(_ item: NSMenuItem) {
        menu.removeItem(item)
        rowItems.removeAll { $0 === item }
        erroredEntries.remove(ObjectIdentifier(item))
        updateGlyph()
        if rowItems.isEmpty && footerItems.isEmpty { deactivate() }
    }

    /// Rolls one row's error state into the shared item's glyph (issue #45 UX
    /// follow-up: a child plugin's ⚠️ was otherwise invisible from the menu
    /// bar itself). Restores the normal glyph the moment no row is left in
    /// error.
    func setEntryError(_ item: NSMenuItem, hasError: Bool) {
        if hasError {
            erroredEntries.insert(ObjectIdentifier(item))
        } else {
            erroredEntries.remove(ObjectIdentifier(item))
        }
        updateGlyph()
    }

    /// Folds `MainMenuController`'s own app-controls menu under this shared
    /// item (issue #71 — one icon total while compact mode is on, not two
    /// side by side): a separator, then the identical rows `target`'s own
    /// standalone menu shows, built from the same seam
    /// (`MainMenuController.buildAppItems`) so the two can never drift apart.
    /// Idempotent — installing while already installed is a no-op, so a
    /// notification storm (`AppController`'s mode-change observer) can never
    /// duplicate the footer. Keeps the shared status item alive even with
    /// zero plugin rows, since it's now the ONLY status item while compact
    /// mode is on.
    func installFooter(target: MainMenuController) {
        guard footerItems.isEmpty else { return }
        var installed: [NSMenuItem] = [.separator()]
        menu.addItem(installed[0])
        let before = menu.items.count
        footerLoginItem = MainMenuController.buildAppItems(in: menu, target: target)
        installed.append(contentsOf: menu.items[before...])
        footerItems = installed
        activateIfNeeded()
    }

    /// Reverses `installFooter` — compact mode switched back off. Safe to
    /// call when no footer is installed (no-op), so repeated toggles never
    /// double-remove.
    func removeFooter() {
        guard !footerItems.isEmpty else { return }
        footerItems.forEach { menu.removeItem($0) }
        footerItems = []
        footerLoginItem = nil
        if rowItems.isEmpty { deactivate() }
    }

    /// Keeps the footer's "Launch Vee at Login" checkmark fresh each time the
    /// shared menu is about to open — the compact analog of
    /// `MainMenuController.menuNeedsUpdate`. A no-op while no footer is
    /// installed. Also hides the footer's leading separator when there are no
    /// plugin rows above it (zero enabled plugins), so the menu doesn't open
    /// with a dangling divider at the top.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        footerLoginItem?.state = LoginItemManager.isEnabled ? .on : .off
        footerItems.first?.isHidden = rowItems.isEmpty
    }

    private func updateGlyph() {
        currentSymbolName = erroredEntries.isEmpty ? Self.normalSymbolName : Self.errorSymbolName
        guard let button = statusItem?.button else { return }
        let description = erroredEntries.isEmpty ? "Vee" : "Vee: plugin error"
        let image = NSImage(systemSymbolName: currentSymbolName, accessibilityDescription: description)
        image?.isTemplate = true
        button.image = image
    }

    private func activateIfNeeded() {
        guard attachesStatusItem, statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // The same `NSMenu` instance for the item's whole lifetime — rows are
        // added/removed/updated in place by `addEntry`/`removeEntry`/the owning
        // `StatusItemController`s, never rebuilt wholesale.
        item.menu = menu
        statusItem = item
        updateGlyph()
    }

    private func deactivate() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }
}
