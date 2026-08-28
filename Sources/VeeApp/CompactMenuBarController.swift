import AppKit

/// Vee's home item: the ONE status item Vee shows for itself, always present.
///
/// It hosts two things. Every plugin whose `BarPlacement` is `.folded` renders
/// into a row here instead of getting its own `NSStatusItem` (issue #45 —
/// menu-bar crowding); each row's title/image mirror what a standalone item
/// would show, and its submenu is that plugin's own dropdown, unchanged —
/// `StatusItemController.buildMenu(body:)` is still the single place that is
/// built, reused verbatim for either surface. Beneath the rows sits
/// `MainMenuController`'s app-controls footer (`installFooter`), built from the
/// exact same seam (`MainMenuController.buildAppItems`) so the rows can never
/// drift out of sync with what that controller believes it offers.
///
/// Issue #71 ("one icon total") used to hold only while an opt-in compact mode
/// was on, with `MainMenuController` owning a second icon the rest of the time.
/// It now holds unconditionally: this is the only Vee icon there is, whatever
/// each plugin's placement, so there is no mode to reconcile and no window in
/// which two Vee icons can appear side by side.
///
/// A singleton so any `StatusItemController` (a real plugin or an ephemeral
/// deep-link item) can join or leave as its placement changes, without
/// `AppController`/`PluginCoordinator` needing to know placement exists at all.
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

    /// The item's default glyph — the same primary glyph `MainMenuController`
    /// used to show on its own item, because this is now that icon rather than
    /// a second one beside it.
    static let normalSymbolName = "v.circle.fill"
    /// Swapped in once ≥1 row is in an error state — the same symbol
    /// `StatusItemController.renderError` uses for a standalone item's own
    /// error surface, so the roll-up reads as the same "something's wrong"
    /// cue at either level.
    static let errorSymbolName = "exclamationmark.triangle.fill"

    /// Rows currently reporting an error (by identity), so the item's glyph can
    /// roll up "≥1 folded plugin is erroring" without ever inspecting any row's
    /// own submenu. `removeEntry` clears a row's membership too, so a plugin
    /// that stopped, was disabled, or was re-placed mid-error can't leave the
    /// badge stuck.
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
    /// rows), or empty before it is installed. Tracked so `installFooter` is
    /// idempotent — a second call must never duplicate the rows — and so
    /// `addEntry` knows how many trailing items it must insert above.
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

    /// Removes a previously-added row — its plugin stopped, or its placement
    /// moved it to its own item or out of the menu bar entirely. Tears down the
    /// status item once the last row is gone AND no footer is installed, which
    /// in the running app never happens: the footer is installed for the app's
    /// lifetime, so this item outlives every row. The condition remains for a
    /// test that exercises row bookkeeping with no footer installed.
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

    /// Installs `MainMenuController`'s app-controls rows as this item's
    /// footer: a separator, then the identical rows `target`'s own menu shows,
    /// built from the same seam (`MainMenuController.buildAppItems`) so the two
    /// can never drift apart. Called once, unconditionally, at launch.
    ///
    /// Idempotent — installing while already installed is a no-op — and it
    /// brings the status item up, so Preferences/Quit stay reachable with zero
    /// plugins folded (or zero plugins at all). There is no uninstall: the
    /// footer is what makes this item permanent.
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

    /// Keeps the footer's "Launch Vee at Login" checkmark fresh each time the
    /// shared menu is about to open — the compact analog of
    /// `MainMenuController.menuNeedsUpdate`. A no-op while no footer is
    /// installed. Also hides the footer's leading separator when there are no
    /// plugin rows above it (zero enabled plugins), so the menu doesn't open
    /// with a dangling divider at the top.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        DetachedWindowsMenu.shared.refreshVisibility()
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
