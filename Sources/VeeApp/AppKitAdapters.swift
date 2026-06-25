#if canImport(AppKit)
import AppKit
import VeeProtocol
import VeeServices

/// Thin AppKit implementations of the launcher seams. These COMPILE against
/// AppKit but contain NO branching/business logic — they only translate the
/// coordinator's view models into native widgets and forward user gestures back
/// through the `LauncherIntentHandling` sink. Every decision (filtering, the
/// selection rule, action dispatch) lives in the (tested) `AppCoordinator`; this
/// layer just renders the pushed projection and reports intent. Verified by
/// manual desktop testing (window appearance, menubar, hotkey fire, key routing),
/// not by the headless unit suite.
///
/// Everything here is `@MainActor` because AppKit demands the main thread; the
/// `vee` target builds in Swift 5 language mode so the actor hop is implicit.

// MARK: - Launcher window (NSPanel: search field + list + detail/empty panes)

@MainActor
public final class AppKitLauncherWindow: NSObject, @MainActor LauncherWindowPresenting {

    // The intent sink (the coordinator). Weak: the coordinator owns us, not the
    // reverse. Set via `attach(intentHandler:)`. No behavior lives here — every
    // call forwards a single user gesture.
    private weak var intent: LauncherIntentHandling?

    // The current list projection (source of truth for the table). The view never
    // derives or mutates this; it only mirrors what the coordinator pushes.
    private var items: [ListItemViewModel] = []
    private var selectedID: String?
    /// The primary action of the selected item, used for Return. Recomputed purely
    /// from the pushed projection — it's a lookup, not a decision.
    private var primaryActionForSelection: String? {
        guard let selectedID,
              let item = items.first(where: { $0.id == selectedID }) else { return nil }
        return item.actions.first?.actionId
    }

    // Native widgets.
    private let panel: KeyForwardingPanel
    private let searchField: NSSearchField
    private let tableView: NSTableView
    private let listScroll: NSScrollView
    private let detailScroll: NSScrollView
    private let detailTitleLabel: NSTextField
    private let detailTextView: NSTextView
    private let detailContainer: NSView
    private let emptyTitleLabel: NSTextField
    private let emptyDescriptionLabel: NSTextField
    private let emptyContainer: NSStackView

    // Reuse identifiers (no logic — just constants).
    private static let rowColumnID = NSUserInterfaceItemIdentifier("vee.row")

    public override init() {
        // A borderless, non-activating HUD-style floating panel: the standard
        // launcher shell. Key when shown so the search field takes keystrokes.
        panel = KeyForwardingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView, .hudWindow],
            backing: .buffered,
            defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false

        // Search field at the top.
        searchField = NSSearchField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search…"
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 20, weight: .regular)
        (searchField.cell as? NSSearchFieldCell)?.searchButtonCell = nil

        // List: a single-column, view-based table inside a scroll view.
        tableView = NSTableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.style = .inset
        tableView.rowHeight = 52
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        let column = NSTableColumn(identifier: AppKitLauncherWindow.rowColumnID)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        listScroll = NSScrollView()
        listScroll.translatesAutoresizingMaskIntoConstraints = false
        listScroll.drawsBackground = false
        listScroll.hasVerticalScroller = true
        listScroll.autohidesScrollers = true
        listScroll.documentView = tableView

        // Detail pane: a title + a read-only text view (markdown rendered as
        // plain text, per spec).
        detailTitleLabel = NSTextField(labelWithString: "")
        detailTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        detailTitleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        detailTitleLabel.textColor = .labelColor
        detailTitleLabel.lineBreakMode = .byTruncatingTail

        detailTextView = NSTextView()
        detailTextView.isEditable = false
        detailTextView.isSelectable = true
        detailTextView.drawsBackground = false
        detailTextView.textColor = .labelColor
        detailTextView.font = .systemFont(ofSize: 14)
        detailTextView.textContainerInset = NSSize(width: 4, height: 4)

        detailScroll = NSScrollView()
        detailScroll.translatesAutoresizingMaskIntoConstraints = false
        detailScroll.drawsBackground = false
        detailScroll.hasVerticalScroller = true
        detailScroll.autohidesScrollers = true
        detailScroll.documentView = detailTextView

        detailContainer = NSView()
        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(detailTitleLabel)
        detailContainer.addSubview(detailScroll)

        // Empty-state pane: centered title + description.
        emptyTitleLabel = NSTextField(labelWithString: "")
        emptyTitleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        emptyTitleLabel.alignment = .center
        emptyTitleLabel.textColor = .secondaryLabelColor
        emptyDescriptionLabel = NSTextField(labelWithString: "")
        emptyDescriptionLabel.font = .systemFont(ofSize: 13)
        emptyDescriptionLabel.alignment = .center
        emptyDescriptionLabel.textColor = .tertiaryLabelColor
        emptyDescriptionLabel.lineBreakMode = .byWordWrapping
        emptyDescriptionLabel.maximumNumberOfLines = 0
        emptyContainer = NSStackView(views: [emptyTitleLabel, emptyDescriptionLabel])
        emptyContainer.translatesAutoresizingMaskIntoConstraints = false
        emptyContainer.orientation = .vertical
        emptyContainer.alignment = .centerX
        emptyContainer.spacing = 6

        super.init()

        // Visual material background (rounded, vibrant) behind everything.
        let backdrop = NSVisualEffectView()
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        backdrop.material = .hudWindow
        backdrop.state = .active
        backdrop.blendingMode = .behindWindow
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 12
        backdrop.layer?.masksToBounds = true

        let separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator

        let content = NSView()
        content.addSubview(backdrop)
        content.addSubview(searchField)
        content.addSubview(separator)
        content.addSubview(listScroll)
        content.addSubview(detailContainer)
        content.addSubview(emptyContainer)
        panel.contentView = content

        // Wire delegates/targets. These route gestures into the intent sink; the
        // table data source mirrors `items`.
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
        panel.keyForwardingDelegate = self

        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: content.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),

            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            separator.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),

            listScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            listScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            listScroll.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 4),
            listScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),

            detailContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            detailContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            detailContainer.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            detailContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),

            detailTitleLabel.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            detailTitleLabel.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            detailTitleLabel.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            detailScroll.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            detailScroll.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            detailScroll.topAnchor.constraint(equalTo: detailTitleLabel.bottomAnchor, constant: 8),
            detailScroll.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),

            emptyContainer.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            emptyContainer.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            emptyContainer.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 32),
            emptyContainer.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -32),
        ])

        // Start with nothing shown; the coordinator pushes a projection.
        renderPanes(for: nil)
    }

    // MARK: LauncherWindowPresenting

    public func attach(intentHandler: LauncherIntentHandling) {
        self.intent = intentHandler
    }

    /// Translate the projected surface into native panes. Pure translation: it
    /// mirrors the view model and never decides anything.
    public func setRootViewModel(_ root: RootViewModel?) {
        switch root {
        case .list(let list):
            items = list.items
            selectedID = list.selectedID
            tableView.reloadData()
            syncTableSelection()
        case .detail(let detail):
            detailTitleLabel.stringValue = detail.title ?? ""
            detailTextView.string = detail.markdown
        case .empty(let empty):
            emptyTitleLabel.stringValue = empty.title ?? "No Results"
            emptyDescriptionLabel.stringValue = empty.description ?? ""
        case .some(.none), nil:
            break
        }
        renderPanes(for: root)
    }

    public func showLauncher() {
        layoutAndCenter()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Focus the search field so typing flows immediately.
        panel.makeFirstResponder(searchField)
    }

    public func hideLauncher() {
        panel.orderOut(nil)
    }

    // MARK: - Pane visibility (translation of the case → which view shows)

    private func renderPanes(for root: RootViewModel?) {
        let showList: Bool
        let showDetail: Bool
        let showEmpty: Bool
        switch root {
        case .list:   showList = true;  showDetail = false; showEmpty = false
        case .detail: showList = false; showDetail = true;  showEmpty = false
        case .empty:  showList = false; showDetail = false; showEmpty = true
        case .some(.none), nil: showList = false; showDetail = false; showEmpty = false
        }
        listScroll.isHidden = !showList
        detailContainer.isHidden = !showDetail
        emptyContainer.isHidden = !showEmpty
    }

    // MARK: - Selection mirroring (view model → table)

    /// Reflect the coordinator's `selectedID` in the table without echoing a
    /// `select(id:)` back (guarded so the delegate callback is inert during sync).
    private var isSyncingSelection = false
    private func syncTableSelection() {
        isSyncingSelection = true
        defer { isSyncingSelection = false }
        if let selectedID, let row = items.firstIndex(where: { $0.id == selectedID }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else {
            tableView.deselectAll(nil)
        }
    }

    private func layoutAndCenter() {
        panel.layoutIfNeeded()
        panel.center()
    }

    // MARK: - Gesture forwarding (target/action + double click)

    @objc private func searchFieldChanged() {
        intent?.setQuery(searchField.stringValue)
    }

    @objc private func rowDoubleClicked() {
        invokePrimaryAction()
    }

    /// Invoke the selected item's primary action via the coordinator.
    fileprivate func invokePrimaryAction() {
        guard let actionId = primaryActionForSelection else { return }
        intent?.invoke(action: actionId)
    }
}

// MARK: - Table data source / delegate (mirror items; report selection)

extension AppKitLauncherWindow: NSTableViewDataSource, NSTableViewDelegate {

    public func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    public func tableView(_ tableView: NSTableView,
                          viewFor tableColumn: NSTableColumn?,
                          row: Int) -> NSView? {
        guard row >= 0, row < items.count else { return nil }
        let item = items[row]
        let cell = (tableView.makeView(withIdentifier: AppKitLauncherWindow.rowColumnID, owner: self)
            as? LauncherRowView) ?? LauncherRowView()
        cell.identifier = AppKitLauncherWindow.rowColumnID
        cell.configure(title: item.title,
                       subtitle: item.subtitle,
                       iconSymbolName: item.icon,
                       shortcut: item.actions.first?.shortcut)
        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncingSelection else { return }
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        // Report intent; the coordinator owns the selection rule and will push the
        // authoritative selection back via setRootViewModel.
        intent?.select(id: items[row].id)
    }
}

// MARK: - Search field key routing (arrows/return/esc while typing)

extension AppKitLauncherWindow: NSSearchFieldDelegate {

    /// Route navigation keys out of the field text view so typing stays focused
    /// while ↑/↓ move the list, Return invokes, Esc hides. Returning `true` tells
    /// AppKit we handled the command. Each branch forwards exactly one intent.
    public func control(_ control: NSControl,
                        textView: NSTextView,
                        doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            intent?.moveSelection(by: -1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            intent?.moveSelection(by: 1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            invokePrimaryAction()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hideLauncher()
            return true
        default:
            return false
        }
    }
}

// MARK: - Key-forwarding panel (Esc when the field isn't first responder)

/// A panel that can become key (borderless panels can't by default) and routes a
/// bare Escape to its delegate so the launcher hides even if focus left the field.
@MainActor
final class KeyForwardingPanel: NSPanel {
    weak var keyForwardingDelegate: KeyForwardingPanelDelegate?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        keyForwardingDelegate?.panelDidRequestCancel()
    }
}

@MainActor
protocol KeyForwardingPanelDelegate: AnyObject {
    func panelDidRequestCancel()
}

extension AppKitLauncherWindow: KeyForwardingPanelDelegate {
    func panelDidRequestCancel() { hideLauncher() }
}

// MARK: - Row view (title + subtitle + icon + shortcut)

/// A single list row: SF Symbol icon (or fallback), title, subtitle, and a
/// trailing shortcut hint. Pure presentation — no behavior.
@MainActor
final class LauncherRowView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .labelColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail

        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutLabel.font = .systemFont(ofSize: 12, weight: .regular)
        shortcutLabel.textColor = .tertiaryLabelColor
        shortcutLabel.alignment = .right
        shortcutLabel.setContentHuggingPriority(.required, for: .horizontal)

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        addSubview(iconView)
        addSubview(textStack)
        addSubview(shortcutLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            shortcutLabel.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 8),
            shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(title: String, subtitle: String?, iconSymbolName: String?, shortcut: String?) {
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.isHidden = (subtitle?.isEmpty ?? true)
        shortcutLabel.stringValue = shortcut ?? ""
        iconView.image = LauncherRowView.image(forSymbol: iconSymbolName)
    }

    /// Resolve an SF Symbol name to an image; fall back to a generic glyph so a
    /// missing/unknown name never blanks the row. Pure lookup.
    private static func image(forSymbol name: String?) -> NSImage? {
        if let name, !name.isEmpty,
           let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            return image
        }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
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
