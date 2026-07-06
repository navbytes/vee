import AppKit
import VeeCore
import VeePluginFormat
import VeeMenu
import VeeTrust

/// A small `@objc` target for the per-plugin menu footer (Refresh / Quit).
@MainActor
private final class ControlsTarget: NSObject, NSMenuDelegate {
    let onRefresh: () -> Void
    let onSettings: () -> Void
    let onAbout: () -> Void
    let onReveal: () -> Void
    let onEdit: () -> Void
    let refreshOnOpen: Bool
    init(onRefresh: @escaping () -> Void, onSettings: @escaping () -> Void, onAbout: @escaping () -> Void, onReveal: @escaping () -> Void, onEdit: @escaping () -> Void, refreshOnOpen: Bool) {
        self.onRefresh = onRefresh
        self.onSettings = onSettings
        self.onAbout = onAbout
        self.onReveal = onReveal
        self.onEdit = onEdit
        self.refreshOnOpen = refreshOnOpen
    }
    @objc func refresh() { onRefresh() }
    @objc func settings() { onSettings() }
    @objc func about() { onAbout() }
    @objc func reveal() { onReveal() }
    @objc func edit() { onEdit() }
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

    private var frames: [NSAttributedString] = []
    private var frameIndex = 0
    private var cycleTimer: Timer?
    private let hasSettings: Bool
    private let trustSummary: TrustSummary?
    private let aboutText: String?
    private let aboutURL: URL?

    public init(pluginName: String, handler: MenuActionHandling, hasSettings: Bool = false, trustSummary: TrustSummary? = nil, refreshOnOpen: Bool = false, aboutText: String? = nil, aboutURL: URL? = nil, onRefresh: @escaping () -> Void, onSettings: @escaping () -> Void = {}, onReveal: @escaping () -> Void = {}, onEdit: @escaping () -> Void = {}) {
        self.pluginName = pluginName
        self.hasSettings = hasSettings
        self.trustSummary = trustSummary
        self.aboutText = aboutText
        self.aboutURL = aboutURL
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.actionTarget = MenuActionTarget(handler: handler)
        let name = pluginName
        self.controls = ControlsTarget(
            onRefresh: onRefresh,
            onSettings: onSettings,
            onAbout: { Self.showAbout(name: name, text: aboutText, url: aboutURL) },
            onReveal: onReveal,
            onEdit: onEdit,
            refreshOnOpen: refreshOnOpen
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

    /// Renders a successful refresh.
    public func render(_ output: ParsedOutput) {
        let presentation = TitleRenderer.presentation(for: output.titleLines)
        frames = presentation.frames
        frameIndex = 0
        apply(image: presentation.image)
        startCyclingIfNeeded()
        statusItem.menu = buildMenu(body: output.body)
    }

    /// Renders an error surface (the launcher stays up; the plugin shows ⚠️).
    public func renderError(_ message: String, detail: String? = nil) {
        cycleTimer?.invalidate()
        frames = []
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "error")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.attributedTitle = NSAttributedString(string: "")
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let error = NSMenuItem(title: message, action: nil, keyEquivalent: "")
        error.isEnabled = false
        menu.addItem(error)

        if let detail, !detail.isEmpty {
            let details = NSMenuItem(title: "Show error output…", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for line in detail.split(separator: "\n").prefix(12) {
                let row = NSMenuItem(title: String(line), action: nil, keyEquivalent: "")
                row.isEnabled = false
                submenu.addItem(row)
            }
            details.submenu = submenu
            menu.addItem(details)
        }

        menu.delegate = controls
        appendControls(to: menu)
        statusItem.menu = menu
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
    }

    private func buildMenu(body: [MenuNode]) -> NSMenu {
        let menu = MenuBuilder.build(body, target: actionTarget)
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

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Vee", action: #selector(ControlsTarget.quit), keyEquivalent: "q")
        quit.target = controls
        menu.addItem(quit)
        return menu
    }
}
