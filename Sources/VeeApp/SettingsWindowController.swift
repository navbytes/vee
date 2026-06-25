#if canImport(AppKit)
import AppKit
import VeeServices

/// The Settings window — a thin, tabbed `NSWindowController` over an `NSPanel`.
///
/// It is deliberately LOGIC-FREE: every gesture is forwarded straight to the
/// injected `SettingsModel` (hotkey / history size / blocklist) or `TokenStoring`
/// (plugin tokens), both of which own the behavior and are unit-tested. This
/// controller just builds AppKit views and wires their targets — it is verified
/// manually, not by the test suite.
///
/// Three sections, selected via an `NSTabView`:
///   • **General** — the `HotkeyRecorderView` for the launcher chord.
///   • **Clipboard** — a history-size stepper, an add/remove blocklist table, and
///     an "Ignore Next Copy" button (forwarded to the injected closure).
///   • **Plugins** — one row per known plugin id with a secure token field that
///     writes through `TokenStoring`.
///
/// Spacing/fonts follow the launcher's conventions (a compact, sectioned panel
/// in the spirit of `AppKitAdapters`).
@MainActor
public final class SettingsWindowController: NSWindowController {

    // MARK: Layout tokens (consistent with the launcher's compact spacing)

    private enum UI {
        static let width: CGFloat = 520
        static let height: CGFloat = 420
        static let margin: CGFloat = 22
        static let rowGap: CGFloat = 12
        static let labelWidth: CGFloat = 150
        static let sectionFont: CGFloat = 13
        static let bodyFont: CGFloat = 13
        static let captionFont: CGFloat = 11
    }

    // MARK: Collaborators (injected; the controller holds no behavior)

    private let model: SettingsModel
    private let tokenStore: TokenStoring
    /// Known plugin ids that get a token row on the Plugins tab. `account` is the
    /// label used for each plugin's stored token (the keychain account axis).
    private let knownPlugins: [PluginTokenSpec]
    /// Forwarded when the user taps "Ignore Next Copy" (the app calls
    /// `ClipboardMonitor.ignoreNextCopy()`). Optional so previews can omit it.
    private let onIgnoreNextCopy: (() -> Void)?

    /// Describes one plugin's token slot on the Plugins tab.
    public struct PluginTokenSpec: Sendable {
        public let pluginId: String
        public let displayName: String
        public let account: String
        public init(pluginId: String, displayName: String, account: String = "default") {
            self.pluginId = pluginId
            self.displayName = displayName
            self.account = account
        }
    }

    // MARK: Retained controls (for binding)

    private var recorder: HotkeyRecorderView?
    private var historyStepper: NSStepper?
    private var historyField: NSTextField?
    private var blocklistTable: NSTableView?
    private var blocklistInput: NSTextField?
    /// Live, mutable copy of the blocklist as a sorted array (table data source).
    private var blocklistRows: [String] = []
    /// Secure token fields keyed by plugin id (so we can read them on commit).
    private var tokenFields: [String: NSSecureTextField] = [:]

    // MARK: Init

    public init(model: SettingsModel,
                tokenStore: TokenStoring,
                knownPlugins: [PluginTokenSpec] = SettingsWindowController.defaultKnownPlugins,
                onIgnoreNextCopy: (() -> Void)? = nil) {
        self.model = model
        self.tokenStore = tokenStore
        self.knownPlugins = knownPlugins
        self.onIgnoreNextCopy = onIgnoreNextCopy

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: UI.width, height: UI.height),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered, defer: true)
        panel.title = "Vee Settings"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        super.init(window: panel)
        self.blocklistRows = model.blocklist.sorted()
        buildTabs()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// A reasonable default plugin roster for the token tab. The app overrides
    /// this with the actually-installed plugins when it constructs the controller.
    /// `nonisolated` so it can serve as a default-argument expression.
    public nonisolated static let defaultKnownPlugins: [PluginTokenSpec] = [
        PluginTokenSpec(pluginId: "com.vee.github", displayName: "GitHub"),
        PluginTokenSpec(pluginId: "com.vee.linear", displayName: "Linear"),
        PluginTokenSpec(pluginId: "com.vee.openai", displayName: "OpenAI"),
    ]

    // MARK: Public entry point (the menubar "Settings…" item calls this later)

    /// Show (and focus) the Settings window, re-syncing controls to the model so
    /// it always opens reflecting the current persisted state.
    public func show() {
        syncFromModel()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Tab assembly

    private func buildTabs() {
        guard let content = window?.contentView else { return }
        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false

        let general = NSTabViewItem(identifier: "general")
        general.label = "General"
        general.view = makeGeneralTab()

        let clipboard = NSTabViewItem(identifier: "clipboard")
        clipboard.label = "Clipboard"
        clipboard.view = makeClipboardTab()

        let plugins = NSTabViewItem(identifier: "plugins")
        plugins.label = "Plugins"
        plugins.view = makePluginsTab()

        tabView.addTabViewItem(general)
        tabView.addTabViewItem(clipboard)
        tabView.addTabViewItem(plugins)

        content.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            tabView.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            tabView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    // MARK: General tab (hotkey recorder)

    private func makeGeneralTab() -> NSView {
        let container = paddedContainer()

        let caption = makeSectionLabel("Launcher Hotkey")
        let help = makeCaption("Press the keys you want to use to open Vee.")

        let recorder = HotkeyRecorderView()
        recorder.chord = model.hotkey
        recorder.onChordRecorded = { [weak self] chord in
            // Pure forward — the model persists + notifies.
            self?.model.updateHotkey(chord)
        }
        self.recorder = recorder

        let resetButton = NSButton(title: "Reset to Default", target: self,
                                   action: #selector(resetHotkey))
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.bezelStyle = .rounded

        let stack = NSStackView(views: [caption, help, recorder, resetButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = UI.rowGap
        stack.setCustomSpacing(4, after: caption)

        container.addSubview(stack)
        pinTopLeading(stack, in: container)
        return container
    }

    @objc private func resetHotkey() {
        model.updateHotkey(SettingsModel.defaultHotkey)
        recorder?.chord = model.hotkey
    }

    // MARK: Clipboard tab (history size + blocklist + ignore-next)

    private func makeClipboardTab() -> NSView {
        let container = paddedContainer()

        // History size row: label + stepper + numeric field.
        let historyLabel = makeBodyLabel("History size:")
        let field = NSTextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.alignment = .right
        field.integerValue = model.historySize
        field.target = self
        field.action = #selector(historyFieldChanged)
        field.widthAnchor.constraint(equalToConstant: 64).isActive = true
        self.historyField = field

        let stepper = NSStepper()
        stepper.translatesAutoresizingMaskIntoConstraints = false
        stepper.minValue = 1
        stepper.maxValue = 10_000
        stepper.increment = 10
        stepper.valueWraps = false
        stepper.integerValue = model.historySize
        stepper.target = self
        stepper.action = #selector(historyStepperChanged)
        self.historyStepper = stepper

        let historyRow = NSStackView(views: [historyLabel, field, stepper])
        historyRow.translatesAutoresizingMaskIntoConstraints = false
        historyRow.orientation = .horizontal
        historyRow.spacing = 8

        // Blocklist section.
        let blocklistCaption = makeSectionLabel("Ignored Pasteboard Types")
        let blocklistHelp = makeCaption(
            "UTIs added here are never recorded to clipboard history. Privacy "
            + "conventions (e.g. concealed types) are always ignored regardless.")

        let table = NSTableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.headerView = nil
        table.rowHeight = 22
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("type"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        self.blocklistTable = table

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        scroll.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let input = NSTextField()
        input.translatesAutoresizingMaskIntoConstraints = false
        input.placeholderString = "com.example.secret-type"
        self.blocklistInput = input

        let addButton = NSButton(title: "Add", target: self, action: #selector(addBlocklistType))
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.bezelStyle = .rounded
        let removeButton = NSButton(title: "Remove Selected", target: self,
                                    action: #selector(removeSelectedBlocklistType))
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.bezelStyle = .rounded

        let addRow = NSStackView(views: [input, addButton, removeButton])
        addRow.translatesAutoresizingMaskIntoConstraints = false
        addRow.orientation = .horizontal
        addRow.spacing = 8
        input.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Ignore-next-copy.
        let ignoreButton = NSButton(title: "Ignore Next Copy", target: self,
                                    action: #selector(ignoreNextCopyTapped))
        ignoreButton.translatesAutoresizingMaskIntoConstraints = false
        ignoreButton.bezelStyle = .rounded
        let ignoreHelp = makeCaption("The next copied item will be skipped (one-shot).")

        let stack = NSStackView(views: [
            historyRow,
            separator(),
            blocklistCaption, blocklistHelp, scroll, addRow,
            separator(),
            ignoreButton, ignoreHelp,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = UI.rowGap
        stack.setCustomSpacing(4, after: blocklistCaption)
        stack.setCustomSpacing(4, after: ignoreButton)

        container.addSubview(stack)
        pinTopLeading(stack, in: container, trailing: true)
        // Let the blocklist controls stretch to the container width.
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        addRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return container
    }

    @objc private func historyStepperChanged() {
        let value = historyStepper?.integerValue ?? model.historySize
        model.historySize = value
        historyField?.integerValue = model.historySize
        historyStepper?.integerValue = model.historySize
    }

    @objc private func historyFieldChanged() {
        let value = historyField?.integerValue ?? model.historySize
        model.historySize = value
        historyField?.integerValue = model.historySize
        historyStepper?.integerValue = model.historySize
    }

    @objc private func addBlocklistType() {
        let text = blocklistInput?.stringValue ?? ""
        model.addToBlocklist(text)
        blocklistInput?.stringValue = ""
        reloadBlocklist()
    }

    @objc private func removeSelectedBlocklistType() {
        guard let table = blocklistTable, table.selectedRow >= 0,
              table.selectedRow < blocklistRows.count else { return }
        model.removeFromBlocklist(blocklistRows[table.selectedRow])
        reloadBlocklist()
    }

    @objc private func ignoreNextCopyTapped() {
        onIgnoreNextCopy?()
    }

    private func reloadBlocklist() {
        blocklistRows = model.blocklist.sorted()
        blocklistTable?.reloadData()
    }

    // MARK: Plugins tab (secure token per plugin)

    private func makePluginsTab() -> NSView {
        let container = paddedContainer()

        let caption = makeSectionLabel("Plugin Tokens")
        let help = makeCaption("Tokens are stored securely and used to authenticate plugin requests.")

        var rows: [NSView] = [caption, help]
        for plugin in knownPlugins {
            rows.append(makeTokenRow(for: plugin))
        }

        let stack = NSStackView(views: rows)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = UI.rowGap
        stack.setCustomSpacing(4, after: caption)

        container.addSubview(stack)
        pinTopLeading(stack, in: container, trailing: true)
        for case let row as NSStackView in stack.arrangedSubviews where row !== caption {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return container
    }

    private func makeTokenRow(for plugin: PluginTokenSpec) -> NSView {
        let label = makeBodyLabel(plugin.displayName)
        label.widthAnchor.constraint(equalToConstant: UI.labelWidth).isActive = true

        let field = NSSecureTextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholderString = "Token"
        // Reflect whether a token is already stored (without revealing it).
        if tokenStore.hasToken(plugin: plugin.pluginId, account: plugin.account) {
            field.placeholderString = "•••••••• (saved)"
        }
        field.identifier = NSUserInterfaceItemIdentifier(plugin.pluginId)
        field.target = self
        field.action = #selector(tokenFieldCommitted(_:))
        tokenFields[plugin.pluginId] = field

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveTokenButton(_:)))
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.bezelStyle = .rounded
        saveButton.identifier = NSUserInterfaceItemIdentifier(plugin.pluginId)

        let row = NSStackView(views: [label, field, saveButton])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.spacing = 8
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    @objc private func tokenFieldCommitted(_ sender: NSSecureTextField) {
        guard let pluginId = sender.identifier?.rawValue else { return }
        commitToken(pluginId: pluginId, value: sender.stringValue)
    }

    @objc private func saveTokenButton(_ sender: NSButton) {
        guard let pluginId = sender.identifier?.rawValue,
              let field = tokenFields[pluginId] else { return }
        commitToken(pluginId: pluginId, value: field.stringValue)
    }

    private func commitToken(pluginId: String, value: String) {
        guard let plugin = knownPlugins.first(where: { $0.pluginId == pluginId }) else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            tokenStore.deleteToken(plugin: plugin.pluginId, account: plugin.account)
        } else {
            tokenStore.setToken(trimmed, plugin: plugin.pluginId, account: plugin.account)
        }
        // Clear the visible field and update the placeholder to reflect state.
        if let field = tokenFields[pluginId] {
            field.stringValue = ""
            field.placeholderString = trimmed.isEmpty ? "Token" : "•••••••• (saved)"
        }
    }

    // MARK: - Re-sync controls from the model (on show)

    private func syncFromModel() {
        recorder?.chord = model.hotkey
        historyField?.integerValue = model.historySize
        historyStepper?.integerValue = model.historySize
        reloadBlocklist()
        for plugin in knownPlugins {
            if let field = tokenFields[plugin.pluginId] {
                field.stringValue = ""
                field.placeholderString =
                    tokenStore.hasToken(plugin: plugin.pluginId, account: plugin.account)
                    ? "•••••••• (saved)" : "Token"
            }
        }
    }

    // MARK: - Small view helpers (kept inline; consistent fonts/spacing)

    private func paddedContainer() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    private func pinTopLeading(_ child: NSView, in container: NSView, trailing: Bool = false) {
        var constraints: [NSLayoutConstraint] = [
            child.topAnchor.constraint(equalTo: container.topAnchor, constant: UI.margin),
            child.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: UI.margin),
        ]
        if trailing {
            constraints.append(child.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -UI.margin))
        }
        NSLayoutConstraint.activate(constraints)
    }

    private func makeSectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: UI.sectionFont, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    private func makeBodyLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: UI.bodyFont)
        label.textColor = .labelColor
        return label
    }

    private func makeCaption(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: UI.captionFont)
        label.textColor = .secondaryLabelColor
        label.isSelectable = false
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.boxType = .separator
        return box
    }
}

// MARK: - Blocklist table data source / delegate

extension SettingsWindowController: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int { blocklistRows.count }

    public func tableView(_ tableView: NSTableView,
                          viewFor tableColumn: NSTableColumn?,
                          row: Int) -> NSView? {
        guard row >= 0, row < blocklistRows.count else { return nil }
        let id = NSUserInterfaceItemIdentifier("blocklist.cell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField)
            ?? {
                let field = NSTextField(labelWithString: "")
                field.identifier = id
                field.font = .systemFont(ofSize: 12)
                field.lineBreakMode = .byTruncatingMiddle
                return field
            }()
        cell.stringValue = blocklistRows[row]
        return cell
    }
}

#endif
