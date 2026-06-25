#if canImport(AppKit)
import AppKit
import VeeProtocol
import VeeServices

/// Thin AppKit implementations of the launcher seams. These COMPILE against
/// AppKit but contain NO branching/business logic — they only translate the
/// coordinator's view models into native widgets and forward user gestures back
/// through the `LauncherIntentHandling` sink. Every decision (filtering, the
/// selection rule, action dispatch) lives in the (tested) `AppCoordinator`; this
/// layer just renders the pushed projection and reports intent.
///
/// Everything here is `@MainActor` because AppKit demands the main thread.

// MARK: - Design tokens (one place to tune the look)

private enum UI {
    static let panelWidth: CGFloat = 720
    static let panelHeight: CGFloat = 470
    static let cornerRadius: CGFloat = 14
    static let rowHeight: CGFloat = 48
    static let contentInset: CGFloat = 8          // list inset from panel edges
    static let searchFont: CGFloat = 22
    static let titleFont: CGFloat = 14
    static let subtitleFont: CGFloat = 12
    static let iconSize: CGFloat = 28
    static let rowCornerRadius: CGFloat = 9
}

// MARK: - Launcher window (NSPanel: search field + list + detail/empty panes)

@MainActor
public final class AppKitLauncherWindow: NSObject, @MainActor LauncherWindowPresenting {

    private weak var intent: LauncherIntentHandling?

    private var items: [ListItemViewModel] = []
    private var selectedID: String?
    private var primaryActionForSelection: String? {
        guard let selectedID,
              let item = items.first(where: { $0.id == selectedID }) else { return nil }
        return item.actions.first?.actionId
    }

    // Native widgets.
    private let panel: KeyForwardingPanel
    private let searchField: NSTextField
    private let magnifier: NSImageView
    private let tableView: NSTableView
    private let listScroll: NSScrollView
    private let detailScroll: NSScrollView
    private let detailTitleLabel: NSTextField
    private let detailTextView: NSTextView
    private let detailContainer: NSView
    private let emptyTitleLabel: NSTextField
    private let emptyDescriptionLabel: NSTextField
    private let emptyContainer: NSStackView
    private let footer: LauncherFooterView
    private let headerSeparator: NSBox
    private let footerSeparator: NSBox

    private static let rowColumnID = NSUserInterfaceItemIdentifier("vee.row")

    public override init() {
        // A borderless, non-activating HUD-style floating panel.
        panel = KeyForwardingPanel(
            contentRect: NSRect(x: 0, y: 0, width: UI.panelWidth, height: UI.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
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

        // Borderless, flush search field (no bezel) — Raycast-style.
        searchField = NSTextField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: UI.searchFont, weight: .regular)
        searchField.textColor = .labelColor
        searchField.placeholderString = "Search for apps and commands…"
        searchField.lineBreakMode = .byTruncatingTail
        searchField.usesSingleLineMode = true
        searchField.cell?.wraps = false
        searchField.cell?.isScrollable = true

        magnifier = NSImageView()
        magnifier.translatesAutoresizingMaskIntoConstraints = false
        magnifier.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")
        magnifier.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        magnifier.contentTintColor = .secondaryLabelColor

        // List: single-column view-based table.
        tableView = NSTableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.style = .inset
        tableView.rowHeight = UI.rowHeight
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
        listScroll.automaticallyAdjustsContentInsets = false
        listScroll.contentInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        listScroll.documentView = tableView

        // Detail pane.
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

        // Empty-state pane.
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

        footer = LauncherFooterView()
        footer.translatesAutoresizingMaskIntoConstraints = false

        headerSeparator = NSBox()
        headerSeparator.translatesAutoresizingMaskIntoConstraints = false
        headerSeparator.boxType = .separator
        footerSeparator = NSBox()
        footerSeparator.translatesAutoresizingMaskIntoConstraints = false
        footerSeparator.boxType = .separator

        super.init()

        // Vibrant rounded backdrop behind everything.
        let backdrop = NSVisualEffectView()
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        backdrop.material = .sidebar
        backdrop.state = .active
        backdrop.blendingMode = .behindWindow
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = UI.cornerRadius
        backdrop.layer?.masksToBounds = true

        let content = NSView()
        content.wantsLayer = true
        content.addSubview(backdrop)
        content.addSubview(magnifier)
        content.addSubview(searchField)
        content.addSubview(headerSeparator)
        content.addSubview(listScroll)
        content.addSubview(detailContainer)
        content.addSubview(emptyContainer)
        content.addSubview(footerSeparator)
        content.addSubview(footer)
        panel.contentView = content

        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        searchField.delegate = self
        panel.keyForwardingDelegate = self

        let footerHeight: CGFloat = 38
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: content.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            magnifier.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            magnifier.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            magnifier.widthAnchor.constraint(equalToConstant: 20),
            magnifier.heightAnchor.constraint(equalToConstant: 20),

            searchField.leadingAnchor.constraint(equalTo: magnifier.trailingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),

            headerSeparator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            headerSeparator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            headerSeparator.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 16),

            listScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: UI.contentInset),
            listScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -UI.contentInset),
            listScroll.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor),
            listScroll.bottomAnchor.constraint(equalTo: footerSeparator.topAnchor),

            detailContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            detailContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            detailContainer.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor, constant: 8),
            detailContainer.bottomAnchor.constraint(equalTo: footerSeparator.topAnchor, constant: -8),

            detailTitleLabel.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            detailTitleLabel.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            detailTitleLabel.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            detailScroll.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            detailScroll.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            detailScroll.topAnchor.constraint(equalTo: detailTitleLabel.bottomAnchor, constant: 8),
            detailScroll.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),

            emptyContainer.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            emptyContainer.centerYAnchor.constraint(equalTo: listScroll.centerYAnchor),
            emptyContainer.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 32),
            emptyContainer.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -32),

            footerSeparator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footerSeparator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            footer.topAnchor.constraint(equalTo: footerSeparator.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: footerHeight),
        ])

        renderPanes(for: nil)
    }

    // MARK: LauncherWindowPresenting

    public func attach(intentHandler: LauncherIntentHandling) {
        self.intent = intentHandler
    }

    public func setRootViewModel(_ root: RootViewModel?) {
        switch root {
        case .list(let list):
            items = list.items
            selectedID = list.selectedID
            tableView.reloadData()
            syncTableSelection()
            footer.update(primaryTitle: selectedPrimaryActionTitle(), hasItems: !items.isEmpty)
        case .detail(let detail):
            detailTitleLabel.stringValue = detail.title ?? ""
            detailTextView.string = detail.markdown
            footer.update(primaryTitle: nil, hasItems: false)
        case .empty(let empty):
            emptyTitleLabel.stringValue = empty.title ?? "No Results"
            emptyDescriptionLabel.stringValue = empty.description ?? ""
            footer.update(primaryTitle: nil, hasItems: false)
        case .some(.none), nil:
            footer.update(primaryTitle: nil, hasItems: false)
        }
        renderPanes(for: root)
    }

    private func selectedPrimaryActionTitle() -> String? {
        guard let selectedID, let item = items.first(where: { $0.id == selectedID }) else { return nil }
        return item.actions.first?.title
    }

    public func showLauncher() {
        layoutAndCenter()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(searchField)
    }

    public func hideLauncher() {
        panel.orderOut(nil)
    }

    // MARK: - Pane visibility

    private func renderPanes(for root: RootViewModel?) {
        let showList: Bool, showDetail: Bool, showEmpty: Bool
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

    // MARK: - Selection mirroring

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

    // MARK: - Gesture forwarding

    @objc private func rowDoubleClicked() { invokePrimaryAction() }

    fileprivate func invokePrimaryAction() {
        guard let actionId = primaryActionForSelection else { return }
        intent?.invoke(action: actionId)
    }

    // MARK: - Offscreen snapshot (autonomous visual testing / regression)

    /// Render the launcher's content offscreen to a PNG. Drives the
    /// `VEE_SNAPSHOT_OUT` harness so the UI can be verified/iterated without a
    /// live desktop. The vibrant backdrop doesn't render offscreen, so we
    /// composite the cached view tree over a solid, appearance-matched fill.
    public func writeSnapshot(to url: URL, size: NSSize, dark: Bool) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        if let appearance { panel.appearance = appearance }
        panel.setContentSize(size)
        guard let content = panel.contentView else { return }
        if let appearance { content.appearance = appearance }
        content.frame = NSRect(origin: .zero, size: size)
        content.layoutSubtreeIfNeeded()
        tableView.reloadData()
        syncTableSelection()
        content.layoutSubtreeIfNeeded()

        let bounds = content.bounds
        guard let rep = content.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        content.cacheDisplay(in: bounds, to: rep)

        let image = NSImage(size: size)
        image.lockFocus()
        (dark ? NSColor(calibratedWhite: 0.12, alpha: 1) : NSColor(calibratedWhite: 0.97, alpha: 1)).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size),
                     xRadius: UI.cornerRadius, yRadius: UI.cornerRadius).fill()
        rep.draw(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              let png = bmp.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}

// MARK: - Table data source / delegate

extension AppKitLauncherWindow: NSTableViewDataSource, NSTableViewDelegate {

    public func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        LauncherSelectionRowView()
    }

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
                       icon: item.icon,
                       shortcut: item.actions.first?.shortcut)
        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncingSelection else { return }
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        intent?.select(id: items[row].id)
    }
}

// MARK: - Search field key routing

extension AppKitLauncherWindow: NSTextFieldDelegate {

    public func controlTextDidChange(_ obj: Notification) {
        intent?.setQuery(searchField.stringValue)
    }

    public func control(_ control: NSControl,
                        textView: NSTextView,
                        doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            intent?.moveSelection(by: -1); return true
        case #selector(NSResponder.moveDown(_:)):
            intent?.moveSelection(by: 1); return true
        case #selector(NSResponder.insertNewline(_:)):
            invokePrimaryAction(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            hideLauncher(); return true
        default:
            return false
        }
    }
}

// MARK: - Key-forwarding panel

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

// MARK: - Selection row view (rounded, neutral — never the emphasized blue)

/// Draws the Raycast-style soft rounded selection pill regardless of focus, so
/// the selected row reads the same whether or not the table is key (and in the
/// offscreen snapshot).
@MainActor
final class LauncherSelectionRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { false }            // keep selection neutral, never the system blue
        set { }
    }
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none, isSelected else { return }
        let rect = bounds.insetBy(dx: 6, dy: 1)
        let path = NSBezierPath(roundedRect: rect,
                                xRadius: UI.rowCornerRadius, yRadius: UI.rowCornerRadius)
        NSColor.unemphasizedSelectedContentBackgroundColor.setFill()
        path.fill()
    }
}

// MARK: - Row view (real app icon + title + subtitle + shortcut)

@MainActor
final class LauncherRowView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) { super.init(frame: frameRect); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: UI.titleFont, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: UI.subtitleFont)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail

        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutLabel.font = .systemFont(ofSize: 12, weight: .regular)
        shortcutLabel.textColor = .tertiaryLabelColor
        shortcutLabel.alignment = .right
        shortcutLabel.setContentHuggingPriority(.required, for: .horizontal)
        shortcutLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        addSubview(iconView)
        addSubview(textStack)
        addSubview(shortcutLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: UI.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: UI.iconSize),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            shortcutLabel.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 8),
            shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(title: String, subtitle: String?, icon: String?, shortcut: String?) {
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.isHidden = (subtitle?.isEmpty ?? true)
        shortcutLabel.stringValue = shortcut ?? ""
        let (image, isRealIcon) = LauncherRowView.resolveIcon(icon)
        iconView.image = image
        // Real app icons are full-color; SF-symbol fallbacks tint to the label color.
        iconView.contentTintColor = isRealIcon ? nil : .secondaryLabelColor
    }

    /// Resolve an icon hint to an image + whether it's a real (file-based) icon.
    /// A filesystem path → the real app/file icon (full color); otherwise an SF
    /// Symbol; otherwise a generic fallback glyph. Pure lookup.
    static func resolveIcon(_ hint: String?) -> (NSImage?, Bool) {
        if let hint, !hint.isEmpty {
            if hint.hasPrefix("/"), FileManager.default.fileExists(atPath: hint) {
                // Pre-rasterize into a fixed-size bitmap so the icon draws crisply
                // and synchronously (IconServices reps otherwise render lazily,
                // which blanks them in an offscreen capture).
                let icon = NSWorkspace.shared.icon(forFile: hint)
                let target = NSImage(size: NSSize(width: UI.iconSize, height: UI.iconSize))
                target.lockFocus()
                NSGraphicsContext.current?.imageInterpolation = .high
                icon.draw(in: NSRect(x: 0, y: 0, width: UI.iconSize, height: UI.iconSize),
                          from: .zero, operation: .sourceOver, fraction: 1)
                target.unlockFocus()
                return (target, true)
            }
            if let image = NSImage(systemSymbolName: hint, accessibilityDescription: nil) {
                return (image, false)
            }
        }
        return (NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil), false)
    }
}

// MARK: - Footer / action bar (primary action + ⌘K hint)

/// A slim bottom bar echoing Raycast: the selected item's primary action on the
/// right with a ↩ glyph, and an "Actions ⌘K" affordance. Pure presentation.
@MainActor
final class LauncherFooterView: NSView {
    private let primaryLabel = NSTextField(labelWithString: "")
    private let returnGlyph = NSTextField(labelWithString: "↩")
    private let actionsLabel = NSTextField(labelWithString: "Actions")
    private let actionsKey = NSTextField(labelWithString: "⌘K")

    override init(frame frameRect: NSRect) { super.init(frame: frameRect); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        for label in [primaryLabel, returnGlyph, actionsLabel, actionsKey] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = .systemFont(ofSize: 12, weight: .regular)
            label.textColor = .tertiaryLabelColor
        }
        primaryLabel.textColor = .secondaryLabelColor
        returnGlyph.textColor = .secondaryLabelColor

        addSubview(primaryLabel)
        addSubview(returnGlyph)
        addSubview(actionsKey)
        addSubview(actionsLabel)

        NSLayoutConstraint.activate([
            primaryLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            primaryLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            returnGlyph.leadingAnchor.constraint(equalTo: primaryLabel.trailingAnchor, constant: 6),
            returnGlyph.centerYAnchor.constraint(equalTo: centerYAnchor),

            actionsKey.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            actionsKey.centerYAnchor.constraint(equalTo: centerYAnchor),
            actionsLabel.trailingAnchor.constraint(equalTo: actionsKey.leadingAnchor, constant: -6),
            actionsLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func update(primaryTitle: String?, hasItems: Bool) {
        primaryLabel.stringValue = primaryTitle ?? (hasItems ? "Open" : "")
        primaryLabel.isHidden = (primaryTitle == nil && !hasItems)
        returnGlyph.isHidden = primaryLabel.isHidden
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
        // Prefer a crisp template glyph over a text title in the menu bar.
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkle.magnifyingglass",
                                   accessibilityDescription: "Vee")
                ?? NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Vee")
            button.image?.isTemplate = true
        }
    }

    public func setMenuBarTitle(_ title: String?) {
        // Keep the glyph; only show text if explicitly provided non-empty.
        if let title, !title.isEmpty { statusItem.button?.title = " \(title)" }
        else { statusItem.button?.title = "" }
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
