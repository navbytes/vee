import AppKit
import VeeCore
import VeePluginFormat
import VeeMenu
import VeeSearch
import VeeTrust

/// A small `@objc` target for the per-plugin menu footer (Refresh / Quit).
@MainActor
private final class ControlsTarget: NSObject, NSMenuDelegate {
    let onRefresh: () -> Void
    let onSettings: () -> Void
    let onAbout: () -> Void
    let onReveal: () -> Void
    let onEdit: () -> Void
    let onDebug: () -> Void
    let onSearch: () -> Void
    let refreshOnOpen: Bool
    init(onRefresh: @escaping () -> Void, onSettings: @escaping () -> Void, onAbout: @escaping () -> Void, onReveal: @escaping () -> Void, onEdit: @escaping () -> Void, onDebug: @escaping () -> Void, onSearch: @escaping () -> Void, refreshOnOpen: Bool) {
        self.onRefresh = onRefresh
        self.onSettings = onSettings
        self.onAbout = onAbout
        self.onReveal = onReveal
        self.onEdit = onEdit
        self.onDebug = onDebug
        self.onSearch = onSearch
        self.refreshOnOpen = refreshOnOpen
    }
    @objc func refresh() { onRefresh() }
    @objc func settings() { onSettings() }
    @objc func about() { onAbout() }
    @objc func reveal() { onReveal() }
    @objc func edit() { onEdit() }
    @objc func debug() { onDebug() }
    @objc func search() { onSearch() }
    @objc func quit() { NSApp.terminate(nil) }

    // <swiftbar.refreshOnOpen>: re-run the plugin when its menu is opened.
    func menuWillOpen(_ menu: NSMenu) {
        if refreshOnOpen { onRefresh() }
    }
}

/// Owns one `NSStatusItem` and renders a plugin's parsed output into it: the
/// (optionally cycling) title, an icon, and the dropdown menu.
@MainActor
public final class StatusItemController {
    private let statusItem: NSStatusItem
    private let pluginName: String
    private let actionTarget: MenuActionTarget
    private let controls: ControlsTarget
    /// Kept so the search panel can dispatch a row through the same handler the
    /// menu uses (the menu's action target already retains it strongly too).
    private let handler: MenuActionHandling
    /// Whether this plugin opts into the searchable filter panel (`<vee.filter>`).
    private let filterEnabled: Bool
    /// Effective Vee-native features (search panel, active global hotkey) for the
    /// capabilities area. Updated live when the user toggles the hotkey.
    private var features: PluginFeatures
    /// The most recently rendered dropdown tree, frozen into the search panel on
    /// open so it reflects what the user currently sees.
    private var lastBody: [MenuNode] = []

    private var frames: [NSAttributedString] = []
    private var frameIndex = 0
    private var cycleTimer: Timer?
    private let hasSettings: Bool
    private let trustSummary: TrustSummary?
    private let aboutText: String?
    private let aboutURL: URL?
    private let hideLastUpdated: Bool
    private var lastUpdated: Date?
    /// The most recently rendered output. `render(_:)` skips rebuilding the
    /// menu/title when a refresh produces byte-identical output — the common
    /// case, since most plugins refresh far more often than their output
    /// actually changes.
    private var lastRendered: ParsedOutput?
    /// The "Updated <time>" stamp row in the controls submenu, kept so an
    /// identical-output render can advance the timestamp in place without
    /// rebuilding the menu.
    private weak var stampItem: NSMenuItem?
    /// Tracks the most recent `setRefreshing` request so the delayed dim
    /// (below) can no-op if the refresh already finished by the time it fires.
    private var isRefreshing = false
    private var dimWorkItem: DispatchWorkItem?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .medium
        f.dateStyle = .none
        return f
    }()

    public init(pluginName: String, handler: MenuActionHandling, hasSettings: Bool = false, trustSummary: TrustSummary? = nil, refreshOnOpen: Bool = false, hideLastUpdated: Bool = false, filterEnabled: Bool = false, features: PluginFeatures = PluginFeatures(), autosaveName: String? = nil, aboutText: String? = nil, aboutURL: URL? = nil, onRefresh: @escaping () -> Void, onSettings: @escaping () -> Void = {}, onReveal: @escaping () -> Void = {}, onEdit: @escaping () -> Void = {}, onDebug: @escaping () -> Void = {}) {
        self.pluginName = pluginName
        self.handler = handler
        self.filterEnabled = filterEnabled
        self.features = features
        self.hasSettings = hasSettings
        self.trustSummary = trustSummary
        self.aboutText = aboutText
        self.aboutURL = aboutURL
        self.hideLastUpdated = hideLastUpdated
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // A stable autosave name lets macOS remember where the user ⌘-dragged
        // this item, so plugin order/position survives relaunch.
        if let autosaveName { self.statusItem.autosaveName = autosaveName }
        self.actionTarget = MenuActionTarget(handler: handler)
        let name = pluginName
        let presentSearch: () -> Void
        // Deferred so the closure can capture the fully-initialized controller.
        var searchPresenter: (() -> Void)?
        presentSearch = { searchPresenter?() }
        self.controls = ControlsTarget(
            onRefresh: onRefresh,
            onSettings: onSettings,
            onAbout: { Self.showAbout(name: name, text: aboutText, url: aboutURL) },
            onReveal: onReveal,
            onEdit: onEdit,
            onDebug: onDebug,
            onSearch: presentSearch,
            refreshOnOpen: refreshOnOpen
        )
        searchPresenter = { [weak self] in self?.presentSearch() }
    }

    /// Flattens the current dropdown tree and opens the searchable filter panel,
    /// routing activations through the same handler the menu uses. Public so a
    /// global hotkey (`<vee.shortcut>`) can open it without the menu being open.
    public func openSearchPanel() { presentSearch() }

    /// Updates the Features shown in the capabilities area and rebuilds the open
    /// menu so a live hotkey change (enable/disable) is reflected immediately.
    public func setFeatures(_ features: PluginFeatures) {
        self.features = features
        if statusItem.menu != nil { statusItem.menu = buildMenu(body: lastBody) }
    }

    private func presentSearch() {
        MenuSearchPanel.shared.present(
            rows: MenuSearch.flatten(lastBody),
            pluginName: pluginName,
            handler: handler
        )
    }

    private static func showAbout(name: String, text: String?, url: URL?) {
        let alert = NSAlert()
        alert.messageText = name
        alert.informativeText = text ?? ""
        alert.addButton(withTitle: "OK")
        if url != nil {
            alert.addButton(withTitle: "Open Website")
        }
        if alert.runModal() == .alertSecondButtonReturn, let url {
            NSWorkspace.shared.open(url)
        }
    }

    /// Renders a successful refresh. Byte-identical output skips rebuilding
    /// the menu/title entirely — only the "Updated" stamp advances.
    public func render(_ output: ParsedOutput) {
        guard output != lastRendered else {
            lastUpdated = Date()
            stampItem?.title = "Updated \(Self.timeFormatter.string(from: Date()))"
            return
        }
        lastRendered = output
        lastUpdated = Date()
        lastBody = output.body
        let presentation = TitleRenderer.presentation(for: output.titleLines)
        frames = presentation.frames
        frameIndex = 0
        apply(image: presentation.image)
        startCyclingIfNeeded()
        statusItem.menu = buildMenu(body: output.body)
    }

    /// Renders an error surface (the launcher stays up; the plugin shows ⚠️).
    public func renderError(_ message: String, detail: String? = nil) {
        // A recovering plugin whose new output happens to equal its
        // pre-error output must still rebuild (the error surface replaced the
        // menu the equality check would otherwise skip re-rendering).
        lastRendered = nil
        cycleTimer?.invalidate()
        frames = []
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "error")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.attributedTitle = NSAttributedString(string: "")
            button.setAccessibilityLabel("\(pluginName): error — \(message)")
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let error = NSMenuItem(title: message, action: nil, keyEquivalent: "")
        error.isEnabled = false
        // Disabled rows can be passed over by VoiceOver; an explicit label keeps
        // the error message and its output readable.
        error.setAccessibilityLabel("Error: \(message)")
        menu.addItem(error)

        if let detail, !detail.isEmpty {
            let details = NSMenuItem(title: "Show error output…", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for line in detail.split(separator: "\n").prefix(12) {
                let row = NSMenuItem(title: String(line), action: nil, keyEquivalent: "")
                row.isEnabled = false
                row.setAccessibilityLabel(String(line))
                submenu.addItem(row)
            }
            details.submenu = submenu
            menu.addItem(details)
        }

        menu.delegate = controls
        appendControls(to: menu)
        statusItem.menu = menu
    }

    /// Surfaces an in-flight refresh: the controls submenu's stamp row (if
    /// present) switches to "Refreshing…", and the status item dims slightly
    /// once the run has been going for >300ms (avoids flicker on fast plugins).
    public func setRefreshing(_ refreshing: Bool) {
        isRefreshing = refreshing
        dimWorkItem?.cancel()

        if let stampItem {
            if refreshing {
                stampItem.title = "Refreshing…"
            } else if let lastUpdated, !hideLastUpdated {
                stampItem.title = "Updated \(Self.timeFormatter.string(from: lastUpdated))"
            }
        }

        guard refreshing else {
            statusItem.button?.alphaValue = 1.0
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRefreshing else { return }
            self.statusItem.button?.alphaValue = 0.55
        }
        dimWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    public func remove() {
        cycleTimer?.invalidate()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Rendering helpers

    private func apply(image: NSImage?) {
        guard let button = statusItem.button else { return }
        button.image = image
        if frames.isEmpty {
            // No title text: show the icon alone, or fall back to the name.
            button.attributedTitle = NSAttributedString(string: image == nil ? pluginName : "")
            button.imagePosition = image == nil ? .noImage : .imageOnly
        } else {
            button.attributedTitle = frames[0]
            button.imagePosition = image == nil ? .noImage : .imageLeading
        }
        updateAccessibilityLabel(currentText: frames.first?.string ?? "")
    }

    /// Give VoiceOver a spoken label for the status item. An icon-only plugin
    /// (image, no title) is otherwise announced only by the icon's generic
    /// description; here we always speak the plugin name plus its live value.
    private func updateAccessibilityLabel(currentText: String) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        statusItem.button?.setAccessibilityLabel(text.isEmpty ? pluginName : "\(pluginName): \(text)")
    }

    private func startCyclingIfNeeded() {
        cycleTimer?.invalidate()
        cycleTimer = nil
        guard frames.count > 1 else { return }
        let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceFrame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        cycleTimer = timer
    }

    private func advanceFrame() {
        guard !frames.isEmpty else { return }
        frameIndex = (frameIndex + 1) % frames.count
        statusItem.button?.attributedTitle = frames[frameIndex]
        updateAccessibilityLabel(currentText: frames[frameIndex].string)
    }

    private func buildMenu(body: [MenuNode]) -> NSMenu {
        let menu = MenuBuilder.build(body, target: actionTarget)
        // Opt-in searchable panel: a "Search…" row at the top opens a filterable,
        // keyboard-driven view of every item — including those nested in
        // submenus — without disturbing the native menu, its trust row, or the
        // controls footer.
        if filterEnabled {
            let search = NSMenuItem(title: "Search…", action: #selector(ControlsTarget.search), keyEquivalent: "f")
            search.target = controls
            let glass = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")
            glass?.isTemplate = true
            search.image = glass
            menu.insertItem(search, at: 0)
            menu.insertItem(.separator(), at: 1)
        }
        appendControls(to: menu)
        menu.delegate = controls
        return menu
    }

    /// A top-of-menu row summarizing what the plugin declares it accesses. Its
    /// submenu lists each capability and any warnings. Advisory only.
    private func buildTrustItem() -> NSMenuItem? {
        // Only surface a row when the plugin declares something; legacy plugins
        // (undeclared) stay uncluttered.
        guard let summary = trustSummary, summary.level != .undeclared else { return nil }

        let item = NSMenuItem()
        let symbol: String
        switch summary.level {
        case .declared: symbol = "checkmark.shield"
        case .partial: symbol = "exclamationmark.shield"
        case .undeclared: symbol = "questionmark.circle"
        }
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.image?.isTemplate = true
        item.title = title(for: summary.level)

        let submenu = NSMenu()
        submenu.autoenablesItems = false
        if summary.badges.isEmpty {
            let note = NSMenuItem(title: "This plugin has not declared what it accesses.", action: nil, keyEquivalent: "")
            note.isEnabled = false
            submenu.addItem(note)
        } else {
            for badge in summary.badges {
                let row = NSMenuItem(title: "\(badge.capability.rawValue): \(badge.detail)", action: nil, keyEquivalent: "")
                row.isEnabled = false
                row.attributedTitle = NSAttributedString(string: row.title, attributes: [.foregroundColor: color(for: badge.severity)])
                submenu.addItem(row)
            }
        }
        for warning in summary.warnings {
            let row = NSMenuItem(title: "⚠︎ \(warning)", action: nil, keyEquivalent: "")
            row.isEnabled = false
            submenu.addItem(row)
        }
        item.submenu = submenu
        return item
    }

    /// A "Features" row mirroring the trust row: lists the Vee-native features
    /// this plugin opts into (searchable menu, global hotkey). Only shown when the
    /// plugin declares at least one, so classic plugins stay uncluttered.
    private func buildFeaturesItem() -> NSMenuItem? {
        guard !features.isEmpty else { return nil }
        let item = NSMenuItem()
        item.title = "Features"
        item.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        item.image?.isTemplate = true

        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for feature in features.items {
            let row = NSMenuItem(title: feature.title, action: nil, keyEquivalent: "")
            row.isEnabled = false
            row.image = NSImage(systemSymbolName: feature.symbol, accessibilityDescription: nil)
            row.image?.isTemplate = true
            row.toolTip = feature.detail
            submenu.addItem(row)
        }
        item.submenu = submenu
        return item
    }

    private func title(for level: TrustLevel) -> String {
        switch level {
        case .declared: return "Capabilities declared"
        case .partial: return "Capabilities incomplete"
        case .undeclared: return "Capabilities undeclared"
        }
    }

    private func color(for severity: Severity) -> NSColor {
        switch severity {
        case .high: return .systemRed
        case .medium: return .systemOrange
        case .low: return .secondaryLabelColor
        }
    }

    /// Appends Vee's own chrome as a *single* trailing item whose submenu holds
    /// the capability summary and all app controls — so a plugin's own output is
    /// what fills its menu, not a stack of Vee-added rows.
    private func appendControls(to menu: NSMenu) {
        if menu.items.contains(where: { !$0.isSeparatorItem }) {
            menu.addItem(.separator())
        }
        let item = NSMenuItem(title: pluginName, action: nil, keyEquivalent: "")
        let gear = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Vee")
        gear?.isTemplate = true
        item.image = gear
        item.submenu = buildControlsSubmenu()
        menu.addItem(item)
    }

    /// The submenu behind the single controls item: capabilities (when declared)
    /// followed by Refresh / Settings / About / Reveal / Edit and Quit.
    private func buildControlsSubmenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let trust = buildTrustItem() {
            menu.addItem(trust)
            menu.addItem(.separator())
        }

        if let featuresItem = buildFeaturesItem() {
            menu.addItem(featuresItem)
            menu.addItem(.separator())
        }

        if !hideLastUpdated, let lastUpdated {
            let stamp = NSMenuItem(title: "Updated \(Self.timeFormatter.string(from: lastUpdated))", action: nil, keyEquivalent: "")
            stamp.isEnabled = false
            menu.addItem(stamp)
            stampItem = stamp
        }

        let refresh = NSMenuItem(title: "Refresh", action: #selector(ControlsTarget.refresh), keyEquivalent: "r")
        refresh.target = controls
        menu.addItem(refresh)

        if hasSettings {
            let settings = NSMenuItem(title: "Settings…", action: #selector(ControlsTarget.settings), keyEquivalent: ",")
            settings.target = controls
            menu.addItem(settings)
        }

        if aboutText != nil || aboutURL != nil {
            let about = NSMenuItem(title: "About \(pluginName)…", action: #selector(ControlsTarget.about), keyEquivalent: "")
            about.target = controls
            menu.addItem(about)
        }

        let reveal = NSMenuItem(title: "Reveal in Finder", action: #selector(ControlsTarget.reveal), keyEquivalent: "")
        reveal.target = controls
        menu.addItem(reveal)

        let edit = NSMenuItem(title: "Edit Plugin…", action: #selector(ControlsTarget.edit), keyEquivalent: "")
        edit.target = controls
        menu.addItem(edit)

        let debug = NSMenuItem(title: "Debug…", action: #selector(ControlsTarget.debug), keyEquivalent: "")
        debug.target = controls
        menu.addItem(debug)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Vee", action: #selector(ControlsTarget.quit), keyEquivalent: "q")
        quit.target = controls
        menu.addItem(quit)
        return menu
    }
}
