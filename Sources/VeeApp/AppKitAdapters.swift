#if canImport(AppKit)
import AppKit
import VeeProtocol
import VeeServices

/// Thin AppKit implementations of the launcher seams. These translate the
/// coordinator's view models into native widgets and forward user gestures back
/// through the `LauncherIntentHandling` sink — no business logic lives here.
///
/// Everything here is `@MainActor` because AppKit demands the main thread.

// MARK: - Design tokens (tuned against Raycast via UX critique cycles)

private enum UI {
    static let panelWidth: CGFloat = 720
    static let panelHeight: CGFloat = 470
    static let cornerRadius: CGFloat = 14
    static let rowHeight: CGFloat = 40
    static let gutter: CGFloat = 20          // shared left edge: search icon, section, row icons
    static let listInset: CGFloat = 4        // scroll view inset; selection pill floats ~10pt from panel edge
    static let searchFont: CGFloat = 20
    static let titleFont: CGFloat = 13
    static let subtitleFont: CGFloat = 12
    static let iconSize: CGFloat = 26
    static let rowCornerRadius: CGFloat = 8
    static let footerHeight: CGFloat = 36
    static let emptyGlyph: CGFloat = 32
}

// MARK: - Launcher window

@MainActor
public final class AppKitLauncherWindow: NSObject, @MainActor LauncherWindowPresenting {

    private weak var intent: LauncherIntentHandling?

    private var items: [ListItemViewModel] = []
    private var selectedID: String?
    private var selectedItem: ListItemViewModel? {
        guard let selectedID else { return nil }
        return items.first(where: { $0.id == selectedID })
    }
    private var primaryActionForSelection: String? { selectedItem?.actions.first?.actionId }

    private let panel: KeyForwardingPanel
    private let searchField: NSTextField
    private let magnifier: NSImageView
    private let sectionLabel: NSTextField
    private let tableView: NSTableView
    private let listScroll: NSScrollView
    private let detailScroll: NSScrollView
    private let detailIconView: NSImageView
    private let detailTitleLabel: NSTextField
    private let detailSubtitleLabel: NSTextField
    private let detailHeaderText: NSStackView
    private let detailHeaderStack: NSStackView
    private let detailHeaderSeparator: NSBox
    private let detailMetadataStack: NSStackView
    private let detailTextView: NSTextView
    private let detailContainer: NSView
    private let emptyGlyph: NSImageView
    private let emptyTitleLabel: NSTextField
    private let emptyDescriptionLabel: NSTextField
    private let emptyContainer: NSStackView
    private let footer: LauncherFooterView
    private let headerSeparator: NSBox
    private let footerSeparator: NSBox
    private var sectionHeightConstraint: NSLayoutConstraint!

    private static let rowColumnID = NSUserInterfaceItemIdentifier("vee.row")

    public override init() {
        panel = KeyForwardingPanel(
            contentRect: NSRect(x: 0, y: 0, width: UI.panelWidth, height: UI.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: true)
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
        magnifier.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        magnifier.contentTintColor = .tertiaryLabelColor

        sectionLabel = NSTextField(labelWithString: "")
        sectionLabel.translatesAutoresizingMaskIntoConstraints = false
        sectionLabel.textColor = .tertiaryLabelColor
        sectionLabel.lineBreakMode = .byTruncatingTail

        tableView = NSTableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.style = .plain
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
        listScroll.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 6, right: 0)
        listScroll.documentView = tableView

        detailIconView = NSImageView()
        detailIconView.translatesAutoresizingMaskIntoConstraints = false
        detailIconView.imageScaling = .scaleProportionallyUpOrDown

        detailTitleLabel = NSTextField(labelWithString: "")
        detailTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        detailTitleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        detailTitleLabel.textColor = .labelColor
        detailTitleLabel.lineBreakMode = .byTruncatingTail

        detailSubtitleLabel = NSTextField(labelWithString: "")
        detailSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        detailSubtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        detailSubtitleLabel.textColor = .secondaryLabelColor
        detailSubtitleLabel.lineBreakMode = .byTruncatingTail

        detailHeaderText = NSStackView(views: [detailTitleLabel, detailSubtitleLabel])
        detailHeaderText.translatesAutoresizingMaskIntoConstraints = false
        detailHeaderText.orientation = .vertical
        detailHeaderText.alignment = .leading
        detailHeaderText.spacing = 1

        detailHeaderStack = NSStackView(views: [detailIconView, detailHeaderText])
        detailHeaderStack.translatesAutoresizingMaskIntoConstraints = false
        detailHeaderStack.orientation = .horizontal
        detailHeaderStack.alignment = .centerY
        detailHeaderStack.spacing = 11

        detailHeaderSeparator = NSBox()
        detailHeaderSeparator.translatesAutoresizingMaskIntoConstraints = false
        detailHeaderSeparator.boxType = .separator

        detailMetadataStack = NSStackView(views: [])
        detailMetadataStack.translatesAutoresizingMaskIntoConstraints = false
        detailMetadataStack.orientation = .vertical
        detailMetadataStack.alignment = .leading
        detailMetadataStack.spacing = 6

        detailTextView = NSTextView()
        detailTextView.isEditable = false
        detailTextView.isSelectable = true
        detailTextView.drawsBackground = false
        detailTextView.textColor = .labelColor
        detailTextView.font = .systemFont(ofSize: 13)
        detailTextView.textContainerInset = NSSize(width: 2, height: 4)

        detailScroll = NSScrollView()
        detailScroll.translatesAutoresizingMaskIntoConstraints = false
        detailScroll.drawsBackground = false
        detailScroll.hasVerticalScroller = true
        detailScroll.autohidesScrollers = true
        detailScroll.documentView = detailTextView

        detailContainer = NSView()
        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(detailHeaderStack)
        detailContainer.addSubview(detailHeaderSeparator)
        detailContainer.addSubview(detailMetadataStack)
        detailContainer.addSubview(detailScroll)

        emptyGlyph = NSImageView()
        emptyGlyph.translatesAutoresizingMaskIntoConstraints = false
        emptyGlyph.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        emptyGlyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: UI.emptyGlyph, weight: .regular)
        emptyGlyph.contentTintColor = .tertiaryLabelColor
        emptyTitleLabel = NSTextField(labelWithString: "")
        emptyTitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        emptyTitleLabel.alignment = .center
        emptyTitleLabel.textColor = .secondaryLabelColor
        emptyDescriptionLabel = NSTextField(labelWithString: "")
        emptyDescriptionLabel.font = .systemFont(ofSize: 13)
        emptyDescriptionLabel.alignment = .center
        emptyDescriptionLabel.textColor = .tertiaryLabelColor
        emptyDescriptionLabel.lineBreakMode = .byWordWrapping
        emptyDescriptionLabel.maximumNumberOfLines = 0
        emptyContainer = NSStackView(views: [emptyGlyph, emptyTitleLabel, emptyDescriptionLabel])
        emptyContainer.translatesAutoresizingMaskIntoConstraints = false
        emptyContainer.orientation = .vertical
        emptyContainer.alignment = .centerX
        emptyContainer.spacing = 10
        emptyContainer.setCustomSpacing(4, after: emptyTitleLabel)

        footer = LauncherFooterView()
        footer.translatesAutoresizingMaskIntoConstraints = false

        headerSeparator = NSBox()
        headerSeparator.translatesAutoresizingMaskIntoConstraints = false
        headerSeparator.boxType = .separator
        footerSeparator = NSBox()
        footerSeparator.translatesAutoresizingMaskIntoConstraints = false
        footerSeparator.boxType = .separator

        super.init()

        sectionLabel.attributedStringValue = NSAttributedString(string: "", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .kern: 0.5,
            .foregroundColor: NSColor.tertiaryLabelColor,
        ])

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
        content.addSubview(sectionLabel)
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

        sectionHeightConstraint = sectionLabel.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: content.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            magnifier.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: UI.gutter),
            magnifier.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            magnifier.widthAnchor.constraint(equalToConstant: 19),
            magnifier.heightAnchor.constraint(equalToConstant: 19),

            searchField.leadingAnchor.constraint(equalTo: magnifier.trailingAnchor, constant: 11),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),

            headerSeparator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            headerSeparator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            headerSeparator.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14),

            sectionLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: UI.gutter),
            sectionLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -UI.gutter),
            sectionLabel.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor, constant: 8),
            sectionHeightConstraint,

            listScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: UI.listInset),
            listScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -UI.listInset),
            listScroll.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 2),
            listScroll.bottomAnchor.constraint(equalTo: footerSeparator.topAnchor),

            detailContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: UI.gutter),
            detailContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -UI.gutter),
            detailContainer.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor, constant: 14),
            detailContainer.bottomAnchor.constraint(equalTo: footerSeparator.topAnchor, constant: -10),

            detailIconView.widthAnchor.constraint(equalToConstant: 40),
            detailIconView.heightAnchor.constraint(equalToConstant: 40),

            detailHeaderStack.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            detailHeaderStack.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            detailHeaderStack.topAnchor.constraint(equalTo: detailContainer.topAnchor),

            detailHeaderSeparator.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            detailHeaderSeparator.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            detailHeaderSeparator.topAnchor.constraint(equalTo: detailHeaderStack.bottomAnchor, constant: 12),

            detailMetadataStack.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            detailMetadataStack.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            detailMetadataStack.topAnchor.constraint(equalTo: detailHeaderSeparator.bottomAnchor, constant: 12),

            detailScroll.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            detailScroll.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            detailScroll.topAnchor.constraint(equalTo: detailMetadataStack.bottomAnchor, constant: 12),
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
            footer.heightAnchor.constraint(equalToConstant: UI.footerHeight),
        ])

        renderPanes(for: nil)
    }

    // MARK: LauncherWindowPresenting

    public func attach(intentHandler: LauncherIntentHandling) { self.intent = intentHandler }

    public func setRootViewModel(_ root: RootViewModel?) {
        switch root {
        case .list(let list):
            items = list.items
            selectedID = list.selectedID
            let title = list.sectionTitle
            let hasTitle = !(title?.isEmpty ?? true)
            sectionLabel.attributedStringValue = NSAttributedString(
                string: (title ?? "").uppercased(),
                attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                             .kern: 0.5, .foregroundColor: NSColor.tertiaryLabelColor])
            sectionLabel.isHidden = !hasTitle
            sectionHeightConstraint.constant = hasTitle ? 15 : 0
            tableView.reloadData()
            syncTableSelection()
            updateFooter()
        case .detail(let detail):
            renderDetail(detail)
            footer.update(icon: nil, primaryTitle: nil, hasItems: false)
        case .empty(let empty):
            emptyTitleLabel.stringValue = empty.title ?? "No Results"
            emptyDescriptionLabel.stringValue = empty.description ?? ""
            footer.update(icon: nil, primaryTitle: nil, hasItems: false)
        case .some(.none), nil:
            footer.update(icon: nil, primaryTitle: nil, hasItems: false)
        }
        renderPanes(for: root)
    }

    private func updateFooter() {
        let item = selectedItem
        let icon = item.flatMap { LauncherRowView.resolveIcon($0.icon).0 }
        footer.update(icon: icon, primaryTitle: item?.actions.first?.title, hasItems: !items.isEmpty)
    }

    /// Populate the detail pane: header (icon + title + optional subtitle), a
    /// hairline, the metadata rail, and the markdown body. Header/metadata
    /// elements collapse (hide) when their data is absent so a bare detail still
    /// reads as a clean title + body.
    private func renderDetail(_ detail: DetailViewModel) {
        detailTitleLabel.stringValue = detail.title ?? ""
        // No subtitle field on the view model yet → header stays title-only.
        detailSubtitleLabel.stringValue = ""
        detailSubtitleLabel.isHidden = true

        if let hint = detail.icon, !hint.isEmpty {
            let (image, isRealIcon) = LauncherRowView.resolveIcon(hint)
            detailIconView.image = image
            detailIconView.contentTintColor = isRealIcon ? nil : .secondaryLabelColor
            detailIconView.isHidden = false
        } else {
            detailIconView.image = nil
            detailIconView.isHidden = true
        }

        rebuildMetadataRows(detail.metadata)
        detailTextView.string = detail.markdown
    }

    /// Rebuild the metadata rail's rows from the view model. Each row is a
    /// label (12pt secondary, right-aligned in a ~90pt column) and a value
    /// (12pt primary). An empty rail hides the separator+stack so the body sits
    /// directly under the header.
    private func rebuildMetadataRows(_ rows: [DetailMetadataRow]) {
        for view in detailMetadataStack.arrangedSubviews {
            detailMetadataStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for row in rows {
            detailMetadataStack.addArrangedSubview(AppKitLauncherWindow.makeMetadataRow(row))
        }
        let hasMetadata = !rows.isEmpty
        detailMetadataStack.isHidden = !hasMetadata
        detailHeaderSeparator.isHidden = !hasMetadata
    }

    /// One label/value metadata row. Label gets a fixed ~90pt right-aligned
    /// column so values line up into a tidy left edge.
    private static func makeMetadataRow(_ row: DetailMetadataRow) -> NSView {
        let label = NSTextField(labelWithString: row.label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.required, for: .horizontal)

        let value = NSTextField(labelWithString: row.value)
        value.translatesAutoresizingMaskIntoConstraints = false
        value.font = .systemFont(ofSize: 12, weight: .regular)
        value.textColor = .labelColor
        value.lineBreakMode = .byTruncatingTail
        value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let rowView = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false
        rowView.addSubview(label)
        rowView.addSubview(value)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: rowView.leadingAnchor),
            label.topAnchor.constraint(equalTo: rowView.topAnchor),
            label.bottomAnchor.constraint(equalTo: rowView.bottomAnchor),
            label.widthAnchor.constraint(equalToConstant: 90),
            value.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 12),
            value.trailingAnchor.constraint(equalTo: rowView.trailingAnchor),
            value.centerYAnchor.constraint(equalTo: label.centerYAnchor),
        ])
        return rowView
    }

    public func showLauncher() {
        searchField.stringValue = ""   // always open on a fresh query
        layoutAndCenter()

        // Capture the centered (final) frame, then start 6pt lower so the panel
        // settles upward as it fades in — a fast, subtle entrance (~0.12s).
        let finalFrame = panel.frame
        let startFrame = finalFrame.offsetBy(dx: 0, dy: -6)

        panel.alphaValue = 0
        panel.setFrame(startFrame, display: false)

        // Subtle ~0.98→1.0 scale-in on the layer-backed content view. AppKit owns
        // the backing layer's anchorPoint/position, so instead of moving the
        // anchor we scale about the layer's center explicitly (translate to
        // center → scale → translate back). That keeps the panel from shifting.
        let contentLayer = panel.contentView?.layer
        if let contentLayer {
            let mid = CGPoint(x: contentLayer.bounds.midX, y: contentLayer.bounds.midY)
            var t = CATransform3DMakeTranslation(mid.x, mid.y, 0)
            t = CATransform3DScale(t, 0.98, 0.98, 1)
            contentLayer.transform = CATransform3DTranslate(t, -mid.x, -mid.y, 0)
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Focus immediately so typing works during the fade (non-blocking).
        panel.makeFirstResponder(searchField)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
            contentLayer?.transform = CATransform3DIdentity
        }
    }

    /// Hide is immediate (no fade) — the launcher should vanish the instant the
    /// user dismisses it. Reset alpha so the next show starts from a clean state.
    public func hideLauncher() {
        panel.orderOut(nil)
        panel.alphaValue = 1
        panel.contentView?.layer?.transform = CATransform3DIdentity
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
        sectionLabel.isHidden = !showList || sectionLabel.stringValue.isEmpty
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

    @objc private func rowDoubleClicked() { invokePrimaryAction() }

    fileprivate func invokePrimaryAction() {
        guard let actionId = primaryActionForSelection else { return }
        intent?.invoke(action: actionId)
    }

    // MARK: - Offscreen snapshot (autonomous visual testing / regression)

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
        cell.configure(title: item.title, subtitle: item.subtitle, icon: item.icon,
                       accessory: item.accessoryText, shortcut: item.actions.first?.shortcut,
                       matchedIndices: item.matchedIndices)
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

    public func control(_ control: NSControl, textView: NSTextView,
                        doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):       intent?.moveSelection(by: -1); return true
        case #selector(NSResponder.moveDown(_:)):     intent?.moveSelection(by: 1); return true
        case #selector(NSResponder.insertNewline(_:)): invokePrimaryAction(); return true
        case #selector(NSResponder.cancelOperation(_:)): hideLauncher(); return true
        default: return false
        }
    }
}

// MARK: - Key-forwarding panel

@MainActor
final class KeyForwardingPanel: NSPanel {
    weak var keyForwardingDelegate: KeyForwardingPanelDelegate?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { keyForwardingDelegate?.panelDidRequestCancel() }
}

@MainActor
protocol KeyForwardingPanelDelegate: AnyObject { func panelDidRequestCancel() }

extension AppKitLauncherWindow: KeyForwardingPanelDelegate {
    func panelDidRequestCancel() { hideLauncher() }
}

// MARK: - Selection row view (accent-tinted rounded pill)

@MainActor
final class LauncherSelectionRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { false }            // keep selection neutral of focus; tint comes from accent below
        set { }
    }
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none, isSelected else { return }
        // Float the pill: inset horizontally so it doesn't run edge-to-edge, and
        // ~4pt vertically so it's ~32pt tall inside a 40pt row.
        let rect = bounds.insetBy(dx: 6, dy: 4)
        let path = NSBezierPath(roundedRect: rect,
                                xRadius: UI.rowCornerRadius, yRadius: UI.rowCornerRadius)
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.11 : 0.13).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.16 : 0.20).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

// MARK: - Row view (real app icon + title + subtitle + accessory)

@MainActor
final class LauncherRowView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let accessoryLabel = NSTextField(labelWithString: "")

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

        accessoryLabel.translatesAutoresizingMaskIntoConstraints = false
        accessoryLabel.font = .systemFont(ofSize: 12, weight: .regular)
        accessoryLabel.textColor = .tertiaryLabelColor
        accessoryLabel.alignment = .right
        accessoryLabel.setContentHuggingPriority(.required, for: .horizontal)
        accessoryLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 0

        addSubview(iconView)
        addSubview(textStack)
        addSubview(accessoryLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UI.gutter - UI.listInset),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: UI.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: UI.iconSize),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 11),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            accessoryLabel.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 8),
            accessoryLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(UI.gutter - UI.listInset)),
            accessoryLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(title: String, subtitle: String?, icon: String?, accessory: String?,
                   shortcut: String?, matchedIndices: [Int] = []) {
        titleLabel.attributedStringValue =
            LauncherRowView.highlightedTitle(title, matchedIndices: matchedIndices)
        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.isHidden = (subtitle?.isEmpty ?? true)
        accessoryLabel.stringValue = accessory ?? shortcut ?? ""
        let (image, isRealIcon) = LauncherRowView.resolveIcon(icon)
        iconView.image = image
        iconView.contentTintColor = isRealIcon ? nil : .secondaryLabelColor
    }

    /// Resolve an icon hint → (image, isRealFileIcon). A filesystem path → the
    /// real (full-color) app/file icon, pre-rasterized at 2× so it draws crisply
    /// and synchronously; otherwise an SF Symbol; otherwise a fallback glyph.
    static func resolveIcon(_ hint: String?) -> (NSImage?, Bool) {
        if let hint, !hint.isEmpty {
            if hint.hasPrefix("/"), FileManager.default.fileExists(atPath: hint) {
                let icon = NSWorkspace.shared.icon(forFile: hint)
                let px = UI.iconSize * 2
                let target = NSImage(size: NSSize(width: UI.iconSize, height: UI.iconSize))
                target.lockFocus()
                NSGraphicsContext.current?.imageInterpolation = .high
                icon.draw(in: NSRect(x: 0, y: 0, width: UI.iconSize, height: UI.iconSize),
                          from: .zero, operation: .sourceOver, fraction: 1)
                target.unlockFocus()
                _ = px
                return (target, true)
            }
            if let image = NSImage(systemSymbolName: hint, accessibilityDescription: nil) {
                return (image, false)
            }
        }
        return (NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil), false)
    }

    /// Render the row title with fuzzy-matched characters accent-tinted +
    /// semibold and the rest in `labelColor`/medium (the row's normal weight).
    /// Empty indices (no query / no match) → a plain medium `labelColor` title,
    /// visually identical to the pre-highlight look. Out-of-range indices are
    /// ignored so a stale match position can never crash or mis-bold.
    static func highlightedTitle(_ title: String, matchedIndices: [Int]) -> NSAttributedString {
        let base = NSFont.systemFont(ofSize: UI.titleFont, weight: .medium)
        let attributed = NSMutableAttributedString(string: title, attributes: [
            .font: base,
            .foregroundColor: NSColor.labelColor,
        ])
        guard !matchedIndices.isEmpty else { return attributed }

        let emphasis = NSFont.systemFont(ofSize: UI.titleFont, weight: .semibold)
        let chars = Array(title)
        for index in matchedIndices where index >= 0 && index < chars.count {
            // Map the character offset onto the string's UTF-16 range so the
            // attribute lands on the right glyph even with multi-unit scalars.
            let start = title.utf16.index(title.utf16.startIndex, offsetBy: index)
            guard let lower = start.samePosition(in: title),
                  lower < title.endIndex else { continue }
            let upper = title.index(after: lower)
            let range = NSRange(lower..<upper, in: title)
            attributed.addAttributes([
                .font: emphasis,
                .foregroundColor: NSColor.controlAccentColor,
            ], range: range)
        }
        return attributed
    }
}

// MARK: - Key cap (rounded chip for ↩ / ⌘K — a Raycast footer signal)

@MainActor
final class KeyCapView: NSView {
    private let label = NSTextField(labelWithString: "")
    init(_ text: String) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.stringValue = text
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 18),
            widthAnchor.constraint(greaterThanOrEqualTo: label.widthAnchor, constant: 10),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 22),  // parity floor for ↩ and ⌘K
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        // Appearance-native chip: `quaternaryLabelColor` resolves to a faint
        // light fill in light mode and a faint light-on-dark fill in dark mode
        // (fixes the inverted dark-on-light caps), with a hairline border.
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 0.5
        layer?.cornerRadius = 5
    }
}

// MARK: - Footer / action bar (selected icon + primary action + key caps)

@MainActor
final class LauncherFooterView: NSView {
    private let iconView = NSImageView()
    private let primaryLabel = NSTextField(labelWithString: "")
    private let returnCap = KeyCapView("↩")
    /// Muted contextual hint shown on the left when there's no selectable primary
    /// action (empty / detail / none) — keeps the bar from reading half-empty.
    private let hintLabel = NSTextField(labelWithString: "")
    private let actionsLabel = NSTextField(labelWithString: "Actions")
    private let actionsCap = KeyCapView("⌘K")

    /// Wordmark shown when no primary action is selectable. Quiet, not a CTA.
    static let idleHint = "Vee"

    override init(frame frameRect: NSRect) { super.init(frame: frameRect); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown

        for label in [primaryLabel, actionsLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = .systemFont(ofSize: 12, weight: .regular)
        }
        primaryLabel.textColor = .secondaryLabelColor
        actionsLabel.textColor = .tertiaryLabelColor

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        // Slightly heavier than the actions hint so the wordmark reads as a quiet
        // brand mark, but still muted (tertiary) so it never competes with "Open".
        hintLabel.font = .systemFont(ofSize: 12, weight: .medium)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.isHidden = true

        addSubview(iconView)
        addSubview(primaryLabel)
        addSubview(returnCap)
        addSubview(hintLabel)
        addSubview(actionsCap)
        addSubview(actionsLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UI.gutter - 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            primaryLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            primaryLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            returnCap.leadingAnchor.constraint(equalTo: primaryLabel.trailingAnchor, constant: 7),
            returnCap.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Hint sits on the shared gutter, same baseline as the primary block.
            hintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UI.gutter - 4),
            hintLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            actionsCap.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            actionsCap.centerYAnchor.constraint(equalTo: centerYAnchor),
            actionsLabel.trailingAnchor.constraint(equalTo: actionsCap.leadingAnchor, constant: -7),
            actionsLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    /// `hint` is the muted left-side text shown when there's no primary action;
    /// defaults to the `Vee` wordmark. The "Actions ⌘K" cluster on the right is
    /// always visible and untouched here.
    func update(icon: NSImage?, primaryTitle: String?, hasItems: Bool,
                hint: String = LauncherFooterView.idleHint) {
        let showPrimary = (primaryTitle != nil) || hasItems
        iconView.image = icon
        iconView.isHidden = (icon == nil) || !showPrimary
        primaryLabel.stringValue = primaryTitle ?? (hasItems ? "Open" : "")
        primaryLabel.isHidden = !showPrimary
        returnCap.isHidden = !showPrimary
        // No selectable primary action → show the contextual hint instead of a
        // blank left half.
        hintLabel.stringValue = hint
        hintLabel.isHidden = showPrimary || hint.isEmpty
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
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkle.magnifyingglass", accessibilityDescription: "Vee")
                ?? NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Vee")
            button.image?.isTemplate = true
        }
    }

    public func setMenuBarTitle(_ title: String?) {
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
