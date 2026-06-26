#if canImport(AppKit)
import AppKit
import VeeServices
import VeeProtocol

/// The Settings window — a thin, tabbed `NSWindowController` over an `NSPanel`.
///
/// It is deliberately LOGIC-FREE: every gesture is forwarded straight to the
/// injected `SettingsModel` (hotkey / history size / blocklist) or
/// `PluginPreferencesStore` (per-extension preferences), both of which own the
/// behavior and are unit-tested. This controller just builds AppKit views and
/// wires their targets — it is verified manually, not by the test suite.
///
/// Three sections, selected via an `NSTabView`:
///   • **General** — the `HotkeyRecorderView` for the launcher chord.
///   • **Clipboard** — a history-size stepper, an add/remove blocklist table, and
///     an "Ignore Next Copy" button (forwarded to the injected closure).
///   • **Extensions** — a GENERIC, plugin-driven preferences pane (the Raycast
///     model). It lists the installed extensions and renders a form from whatever
///     `PluginPreference`s each one DECLARED — text fields, secure fields,
///     checkboxes, dropdowns. The app hardcodes no service or API key; what is
///     configurable is entirely what the plugins declared. Secrets land in the
///     Keychain, the rest in a preferences store (both behind the store).
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
    /// The generic, plugin-driven preferences store backing the Extensions tab.
    /// It knows nothing about any specific service — it operates purely on what
    /// each installed plugin declared.
    private let preferences: PluginPreferencesStore
    /// Forwarded when the user taps "Ignore Next Copy" (the app calls
    /// `ClipboardMonitor.ignoreNextCopy()`). Optional so previews can omit it.
    private let onIgnoreNextCopy: (() -> Void)?

    // MARK: Retained controls (for binding)

    private var recorder: HotkeyRecorderView?
    private var historyStepper: NSStepper?
    private var historyField: NSTextField?
    private var blocklistTable: NSTableView?
    private var blocklistInput: NSTextField?
    private var tabView: NSTabView?
    /// Live, mutable copy of the blocklist as a sorted array (table data source).
    private var blocklistRows: [String] = []

    // MARK: Extensions tab state
    /// Sidebar data: installed extensions, sorted by name.
    private var extensionRows: [PluginManifest] = []
    /// The extensions sidebar list.
    private var extensionsTable: NSTableView?
    /// The right-hand form area, rebuilt when the selected extension changes.
    private var detailContainer: NSView?
    /// The extension whose form is currently shown.
    private var currentExtensionId: String?
    /// Editable controls for the current extension, keyed by preference name.
    private var prefControls: [String: NSView] = [:]
    /// A pluginId to select once the window is shown (the "Setup required" jump).
    private var pendingFocusPluginId: String?

    // MARK: Init

    public init(model: SettingsModel,
                preferences: PluginPreferencesStore,
                onIgnoreNextCopy: (() -> Void)? = nil) {
        self.model = model
        self.preferences = preferences
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
        self.extensionRows = preferences.extensions
        buildTabs()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Public entry point (the menubar "Settings…" item calls this later)

    /// Show (and focus) the Settings window, re-syncing controls to the model so
    /// it always opens reflecting the current persisted state.
    public func show() { show(focusExtension: nil) }

    /// Show Settings; when `focusExtension` is set, jump to the Extensions tab and
    /// select that extension. Used by the launcher's "Setup required" gate so a
    /// command whose required preferences are unset opens straight to its form.
    public func show(focusExtension pluginId: String?) {
        pendingFocusPluginId = pluginId
        syncFromModel()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let pluginId { focusExtension(pluginId) }
    }

    /// Switch to the Extensions tab and select the row for `pluginId`.
    private func focusExtension(_ pluginId: String) {
        guard let index = extensionRows.firstIndex(where: { $0.id == pluginId }) else { return }
        tabView?.selectTabViewItem(withIdentifier: "extensions")
        extensionsTable?.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        showExtensionForm(pluginId: pluginId)
    }

    // MARK: - Tab assembly

    private func buildTabs() {
        guard let content = window?.contentView else { return }
        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        self.tabView = tabView

        let general = NSTabViewItem(identifier: "general")
        general.label = "General"
        general.view = makeGeneralTab()

        let clipboard = NSTabViewItem(identifier: "clipboard")
        clipboard.label = "Clipboard"
        clipboard.view = makeClipboardTab()

        let extensions = NSTabViewItem(identifier: "extensions")
        extensions.label = "Extensions"
        extensions.view = makeExtensionsTab()

        tabView.addTabViewItem(general)
        tabView.addTabViewItem(clipboard)
        tabView.addTabViewItem(extensions)

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

    // MARK: Extensions tab (generic, plugin-declared preferences)

    /// A sidebar list of installed extensions + a detail form rendered from the
    /// selected extension's DECLARED preferences. There is nothing service-
    /// specific here — the form is a pure function of each plugin's manifest.
    private func makeExtensionsTab() -> NSView {
        let container = paddedContainer()

        guard !extensionRows.isEmpty else {
            let empty = makeCaption("No extensions installed.")
            container.addSubview(empty)
            pinTopLeading(empty, in: container, trailing: true)
            return container
        }

        // Sidebar list.
        let table = NSTableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.headerView = nil
        table.rowHeight = 24
        table.allowsEmptySelection = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("extension"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        self.extensionsTable = table

        let sidebar = NSScrollView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.hasVerticalScroller = true
        sidebar.borderType = .bezelBorder
        sidebar.documentView = table
        sidebar.widthAnchor.constraint(equalToConstant: 168).isActive = true

        // Detail form (rebuilt on selection).
        let detail = NSView()
        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.setContentHuggingPriority(.defaultLow, for: .horizontal)
        self.detailContainer = detail

        let row = NSStackView(views: [sidebar, detail])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 16

        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: UI.margin),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: UI.margin),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -UI.margin),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -UI.margin),
            sidebar.topAnchor.constraint(equalTo: row.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])

        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        showExtensionForm(pluginId: extensionRows[0].id)
        return container
    }

    /// Rebuild the detail form for the selected extension from its declared
    /// preferences. This is the generic renderer — it never names a service.
    private func showExtensionForm(pluginId: String) {
        currentExtensionId = pluginId
        prefControls.removeAll()
        guard let detail = detailContainer else { return }
        detail.subviews.forEach { $0.removeFromSuperview() }
        guard let manifest = preferences.manifest(forPlugin: pluginId) else { return }

        let prefs = preferences.declaredPreferences(forPlugin: pluginId)
        var rows: [NSView] = [makeSectionLabel(manifest.name)]

        if prefs.isEmpty {
            rows.append(makeCaption("This extension has no settings to configure."))
        } else {
            // "Setup required" banner when a required preference is still unset.
            let missingRequired = prefs.contains {
                $0.required && $0.default == nil
                    && !preferences.hasStoredValue(pluginId: pluginId, preference: $0)
            }
            if missingRequired {
                let banner = makeCaption("⚠︎ This extension needs setup before its commands can run.")
                banner.textColor = .systemOrange
                rows.append(banner)
            }
            for pref in prefs { rows.append(makePreferenceRow(pluginId: pluginId, pref: pref)) }

            let save = NSButton(title: "Save", target: self, action: #selector(saveExtensionPrefs))
            save.translatesAutoresizingMaskIntoConstraints = false
            save.bezelStyle = .rounded
            save.keyEquivalent = "\r"
            rows.append(save)
        }

        let stack = NSStackView(views: rows)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = UI.rowGap
        stack.setCustomSpacing(8, after: rows[0])

        detail.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: detail.topAnchor),
            stack.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
        ])
        for case let r as NSStackView in stack.arrangedSubviews {
            r.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    /// Build one control row for a declared preference, by its declared type.
    private func makePreferenceRow(pluginId: String, pref: PluginPreference) -> NSView {
        let control: NSView
        switch pref.type {
        case .checkbox:
            let box = NSButton(checkboxWithTitle: pref.label ?? pref.title, target: nil, action: nil)
            box.translatesAutoresizingMaskIntoConstraints = false
            let current = preferences.storedValue(pluginId: pluginId, preference: pref)?.boolValue
                ?? pref.default?.boolValue ?? false
            box.state = current ? .on : .off
            control = box
        case .dropdown:
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.translatesAutoresizingMaskIntoConstraints = false
            for option in pref.data { popup.addItem(withTitle: option.title) }
            let currentValue = preferences.storedValue(pluginId: pluginId, preference: pref)?.stringValue
                ?? pref.default?.stringValue
            if let currentValue, let idx = pref.data.firstIndex(where: { $0.value == currentValue }) {
                popup.selectItem(at: idx)
            }
            control = popup
        case .password:
            let field = NSSecureTextField()
            field.translatesAutoresizingMaskIntoConstraints = false
            field.placeholderString =
                preferences.hasStoredValue(pluginId: pluginId, preference: pref)
                ? "•••••••• (saved)" : (pref.placeholder ?? "Required")
            control = field
        default:  // textfield (+ file/directory/app-picker parity placeholders)
            let field = NSTextField()
            field.translatesAutoresizingMaskIntoConstraints = false
            field.placeholderString = pref.placeholder ?? ""
            field.stringValue = preferences.storedValue(pluginId: pluginId, preference: pref)?.stringValue
                ?? pref.default?.stringValue ?? ""
            control = field
        }
        prefControls[pref.name] = control
        if let tf = control as? NSTextField {
            tf.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
            tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        var columnViews: [NSView] = []
        if pref.type != .checkbox {
            columnViews.append(makeBodyLabel(pref.required ? "\(pref.title) (required)" : pref.title))
        }
        columnViews.append(control)
        if let desc = pref.description, !desc.isEmpty {
            columnViews.append(makeCaption(desc))
        }

        let column = NSStackView(views: columnViews)
        column.translatesAutoresizingMaskIntoConstraints = false
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 4
        return column
    }

    /// Read every control for the current extension and write through the store,
    /// which routes secrets to the Keychain and the rest to the prefs store.
    @objc private func saveExtensionPrefs() {
        guard let pluginId = currentExtensionId else { return }
        for pref in preferences.declaredPreferences(forPlugin: pluginId) {
            guard let control = prefControls[pref.name] else { continue }
            switch pref.type {
            case .checkbox:
                let on = (control as? NSButton)?.state == .on
                preferences.setValue(.bool(on), pluginId: pluginId, preference: pref)
            case .dropdown:
                if let popup = control as? NSPopUpButton, popup.indexOfSelectedItem >= 0,
                   popup.indexOfSelectedItem < pref.data.count {
                    preferences.setValue(.string(pref.data[popup.indexOfSelectedItem].value),
                                         pluginId: pluginId, preference: pref)
                }
            case .password:
                guard let field = control as? NSTextField else { continue }
                let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                // An empty submit leaves an existing secret intact (the field shows
                // "saved" but is blank) — only a non-empty entry overwrites it.
                if !trimmed.isEmpty {
                    preferences.setValue(.string(trimmed), pluginId: pluginId, preference: pref)
                }
            default:
                guard let field = control as? NSTextField else { continue }
                preferences.setValue(.string(field.stringValue), pluginId: pluginId, preference: pref)
            }
        }
        // Rebuild so "saved" placeholders + the setup banner refresh.
        showExtensionForm(pluginId: pluginId)
    }

    // MARK: - Re-sync controls from the model (on show)

    private func syncFromModel() {
        recorder?.chord = model.hotkey
        historyField?.integerValue = model.historySize
        historyStepper?.integerValue = model.historySize
        reloadBlocklist()
        // Re-render the current extension form so "saved" states + the setup
        // banner reflect the latest stored values each time Settings reopens.
        if let id = currentExtensionId ?? extensionRows.first?.id {
            showExtensionForm(pluginId: id)
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
    public func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === extensionsTable ? extensionRows.count : blocklistRows.count
    }

    public func tableView(_ tableView: NSTableView,
                          viewFor tableColumn: NSTableColumn?,
                          row: Int) -> NSView? {
        if tableView === extensionsTable {
            guard row >= 0, row < extensionRows.count else { return nil }
            let id = NSUserInterfaceItemIdentifier("extension.cell")
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField)
                ?? {
                    let field = NSTextField(labelWithString: "")
                    field.identifier = id
                    field.font = .systemFont(ofSize: 13)
                    field.lineBreakMode = .byTruncatingTail
                    return field
                }()
            cell.stringValue = extensionRows[row].name
            return cell
        }
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

    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView, table === extensionsTable else { return }
        let row = table.selectedRow
        guard row >= 0, row < extensionRows.count else { return }
        showExtensionForm(pluginId: extensionRows[row].id)
    }
}

#endif
