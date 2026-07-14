import AppKit
import VeeCore
import VeePluginFormat
import VeeMenu
import VeePreferences
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
    /// Non-nil only in standalone mode (one `NSStatusItem` per plugin, the
    /// default). `nil` while compact mode is active — see `compactEntry`.
    private var statusItem: NSStatusItem?
    /// Non-nil only in compact mode: this plugin's row inside the shared Vee
    /// menu (`CompactMenuBarController`). Mutated directly (title/image/
    /// submenu) the same way `statusItem`'s button/menu are in standalone mode.
    private var compactEntry: NSMenuItem?
    /// The compact row's title with no refresh-dim tint applied — cached so
    /// `applyAlpha` can restore it verbatim, or re-derive the dimmed variant
    /// on every title update (e.g. a cycling frame) while a refresh is still
    /// in flight. `nil` outside compact mode.
    private var compactBaseTitle: NSAttributedString?
    /// Whether the compact row is currently tinted to signal an in-flight
    /// refresh — the row analog of the standalone item's `alphaValue` dim;
    /// `applyAlpha` drives both together.
    private var isCompactDimmed = false
    /// Which surface this controller is currently rendering into. Kept
    /// alongside `statusItem`/`compactEntry` (rather than derived from them)
    /// so `reconcileMode()` has something to compare the live preference
    /// against.
    private var isCompact: Bool
    private let compactController: CompactMenuBarController
    private let prefs: AppPreferences
    /// `nonisolated(unsafe)`: read only from `deinit`, which strict concurrency
    /// treats as non-isolated even for a `@MainActor` class. `deinit` has
    /// exclusive access to the instance (nothing else can be running
    /// concurrently once it starts), so this is safe — the same carve-out
    /// `SymbolImageFactory` uses for its thread-safe `NSCache`.
    private nonisolated(unsafe) var modeObserverToken: NSObjectProtocol?
    /// Re-applied whenever a standalone item is (re)created — at `init` and
    /// when switching back out of compact mode.
    private let autosaveName: String?
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
    /// The last error surfaced (mirrors `lastRendered` for the error path) —
    /// `nil` whenever the plugin is in a good state. Lets a mode switch
    /// (`reconcileMode()`) repaint the right thing on the new surface.
    private var lastErrorMessage: String?
    private var lastErrorDetail: String?
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

    public init(pluginName: String, handler: MenuActionHandling, hasSettings: Bool = false, trustSummary: TrustSummary? = nil, refreshOnOpen: Bool = false, hideLastUpdated: Bool = false, filterEnabled: Bool = false, features: PluginFeatures = PluginFeatures(), autosaveName: String? = nil, aboutText: String? = nil, aboutURL: URL? = nil, onRefresh: @escaping () -> Void, onSettings: @escaping () -> Void = {}, onReveal: @escaping () -> Void = {}, onEdit: @escaping () -> Void = {}, onDebug: @escaping () -> Void = {}, prefs: AppPreferences = .shared, compactController: CompactMenuBarController = .shared) {
        self.pluginName = pluginName
        self.handler = handler
        self.filterEnabled = filterEnabled
        self.features = features
        self.hasSettings = hasSettings
        self.trustSummary = trustSummary
        self.aboutText = aboutText
        self.aboutURL = aboutURL
        self.hideLastUpdated = hideLastUpdated
        self.autosaveName = autosaveName
        self.prefs = prefs
        self.compactController = compactController

        // Compact mode (issue #45): collapse into ONE shared "Vee" status
        // item's dropdown instead of a standalone item, opt-in via Settings.
        // Decided once here and kept live afterward by `reconcileMode()`.
        let compact = prefs.compactMenuBar
        self.isCompact = compact
        if compact {
            self.statusItem = nil
            self.compactEntry = compactController.addEntry()
        } else {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            // A stable autosave name lets macOS remember where the user ⌘-dragged
            // this item, so plugin order/position survives relaunch.
            if let autosaveName { item.autosaveName = autosaveName }
            self.statusItem = item
            self.compactEntry = nil
        }

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

        // Live mode toggle: react to Settings' "Combine all plugins into one
        // menu bar item" switch without a relaunch, for every plugin already
        // running.
        modeObserverToken = NotificationCenter.default.addObserver(
            forName: AppPreferences.compactMenuBarDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcileMode() }
        }
    }

    deinit {
        if let modeObserverToken {
            NotificationCenter.default.removeObserver(modeObserverToken)
        }
    }

    /// Flattens the current dropdown tree and opens the searchable filter panel,
    /// routing activations through the same handler the menu uses. Public so a
    /// global hotkey (`<vee.shortcut>`) can open it without the menu being open.
    public func openSearchPanel() { presentSearch() }

    /// Updates the Features shown in the capabilities area and rebuilds the open
    /// menu so a live hotkey change (enable/disable) is reflected immediately.
    public func setFeatures(_ features: PluginFeatures) {
        self.features = features
        let alreadyRendered = statusItem?.menu != nil || compactEntry?.submenu != nil
        if alreadyRendered { applyMenu(buildMenu(body: lastBody)) }
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
        lastErrorMessage = nil
        lastErrorDetail = nil
        lastUpdated = Date()
        lastBody = output.body
        let presentation = TitleRenderer.presentation(for: output.titleLines)
        frames = presentation.frames
        frameIndex = 0
        apply(image: presentation.image)
        startCyclingIfNeeded()
        applyMenu(buildMenu(body: output.body))
        // Issue #45 UX follow-up: a recovering plugin must clear its share of
        // the shared item's error roll-up (see `renderError` and
        // `CompactMenuBarController.setEntryError`).
        if let compactEntry {
            compactController.setEntryError(compactEntry, hasError: false)
        }
    }

    /// Renders an error surface (the launcher stays up; the plugin shows ⚠️).
    public func renderError(_ message: String, detail: String? = nil) {
        // A recovering plugin whose new output happens to equal its
        // pre-error output must still rebuild (the error surface replaced the
        // menu the equality check would otherwise skip re-rendering).
        lastRendered = nil
        lastErrorMessage = message
        lastErrorDetail = detail
        cycleTimer?.invalidate()
        frames = []
        let image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "error")
        image?.isTemplate = true
        applyPresentation(title: NSAttributedString(string: ""), image: image, imagePosition: .imageOnly)
        applyAccessibilityLabel("\(pluginName): error — \(message)")
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
        applyMenu(menu)
        // Rolls this row's error into the shared item's glyph (issue #45 UX
        // follow-up): the menu bar itself now signals "something's wrong"
        // without the user needing to open every plugin's dropdown to find
        // the ⚠️ row.
        if let compactEntry {
            compactController.setEntryError(compactEntry, hasError: true)
        }
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
            applyAlpha(1.0)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRefreshing else { return }
            self.applyAlpha(0.55)
        }
        dimWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Tears down whichever surface is active — the standalone item, or this
    /// plugin's row in the shared compact menu — and stops observing the
    /// compact-mode preference. Safe to call more than once.
    public func remove() {
        cycleTimer?.invalidate()
        dimWorkItem?.cancel()
        if let modeObserverToken {
            NotificationCenter.default.removeObserver(modeObserverToken)
            self.modeObserverToken = nil
        }
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        if let compactEntry {
            compactController.removeEntry(compactEntry)
            self.compactEntry = nil
        }
    }

    // MARK: - Compact mode (issue #45)

    /// Re-checks the live "collapse into one Vee menu" preference against the
    /// surface this controller is currently rendering into, and switches when
    /// it changed — so toggling Settings takes effect immediately, for every
    /// plugin already running, with no relaunch.
    private func reconcileMode() {
        let wantsCompact = prefs.compactMenuBar
        guard wantsCompact != isCompact else { return }
        isCompact = wantsCompact
        if wantsCompact {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            compactEntry = compactController.addEntry()
        } else {
            if let compactEntry { compactController.removeEntry(compactEntry) }
            compactEntry = nil
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let autosaveName { item.autosaveName = autosaveName }
            statusItem = item
        }
        repaintCurrentSurface()
    }

    /// Re-renders the last known state (a success or an error) into whichever
    /// surface `reconcileMode()` just switched to, so it isn't left blank
    /// until the plugin's next scheduled refresh.
    private func repaintCurrentSurface() {
        if let lastErrorMessage {
            renderError(lastErrorMessage, detail: lastErrorDetail)
        } else if let lastRendered {
            apply(image: TitleRenderer.presentation(for: lastRendered.titleLines).image)
            applyMenu(buildMenu(body: lastRendered.body))
        }
    }

    // MARK: - Rendering helpers

    private func apply(image: NSImage?) {
        if frames.isEmpty {
            // No title text: show the icon alone, or fall back to the name.
            applyPresentation(
                title: NSAttributedString(string: image == nil ? pluginName : ""),
                image: image,
                imagePosition: image == nil ? .noImage : .imageOnly
            )
        } else {
            applyPresentation(title: frames[0], image: image, imagePosition: image == nil ? .noImage : .imageLeading)
        }
        updateAccessibilityLabel(currentText: frames.first?.string ?? "")
    }

    /// Applies a title + image to whichever surface is active. `imagePosition`
    /// only means anything for a real status-bar button (icon-only vs.
    /// icon-leading-text); a compact-mode row is an `NSMenuItem`, which always
    /// shows its image beside its title, so that argument is simply ignored
    /// there.
    private func applyPresentation(title: NSAttributedString, image: NSImage?, imagePosition: NSControl.ImagePosition) {
        if let button = statusItem?.button {
            button.image = image
            button.attributedTitle = title
            button.imagePosition = imagePosition
        } else if let compactEntry {
            compactEntry.image = image
            // ponytail: a blank title reads fine alone in the real menu bar
            // (the icon carries it) but is ambiguous stacked among sibling
            // rows in one shared menu — fall back to the plugin name so every
            // row stays identifiable.
            setCompactTitle(title.string.isEmpty ? NSAttributedString(string: pluginName) : title)
        }
    }

    /// Cycling-frame update: title text only (image/position don't change
    /// between frames of the same render). See `applyPresentation` for the
    /// full-render path.
    private func applyTitleText(_ title: NSAttributedString) {
        if let button = statusItem?.button {
            button.attributedTitle = title
        } else if compactEntry != nil {
            setCompactTitle(title.string.isEmpty ? NSAttributedString(string: pluginName) : title)
        }
    }

    /// Stores `title` as the compact row's undimmed content and paints it,
    /// re-applying the refresh-in-progress tint (see `applyAlpha`) if one is
    /// currently active — so a cycling frame mid-refresh doesn't clear the
    /// dim early.
    private func setCompactTitle(_ title: NSAttributedString) {
        compactBaseTitle = title
        compactEntry?.attributedTitle = isCompactDimmed ? Self.dimmed(title) : title
    }

    /// The compact-row analog of dimming a standalone button's `alphaValue`:
    /// a menu item has no such property, so the same "in flight" cue is
    /// carried by tinting its title text instead.
    private static func dimmed(_ title: NSAttributedString) -> NSAttributedString {
        let tinted = NSMutableAttributedString(attributedString: title)
        tinted.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSRange(location: 0, length: tinted.length))
        return tinted
    }

    /// Assigns a freshly built dropdown to whichever surface is active. In
    /// compact mode this only ever replaces THIS plugin's row, never the
    /// shared top-level menu itself, so a sibling plugin's open submenu is
    /// never disturbed by this one refreshing.
    private func applyMenu(_ menu: NSMenu) {
        if statusItem != nil {
            statusItem?.menu = menu
        } else {
            compactEntry?.submenu = menu
        }
    }

    /// Dims the status-bar button while a refresh is in flight. A compact-mode
    /// row has no `alphaValue` of its own, so the same cue is carried by
    /// tinting its title text instead — on top of the "Refreshing…" stamp its
    /// own submenu already carries (see `stampItem`), which stays two levels
    /// deep and easy to miss.
    private func applyAlpha(_ alpha: CGFloat) {
        statusItem?.button?.alphaValue = alpha
        isCompactDimmed = alpha < 1
        if let compactBaseTitle {
            compactEntry?.attributedTitle = isCompactDimmed ? Self.dimmed(compactBaseTitle) : compactBaseTitle
        }
    }

    /// Give VoiceOver a spoken label for the status item. An icon-only plugin
    /// (image, no title) is otherwise announced only by the icon's generic
    /// description; here we always speak the plugin name plus its live value.
    private func updateAccessibilityLabel(currentText: String) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        applyAccessibilityLabel(text.isEmpty ? pluginName : "\(pluginName): \(text)")
    }

    private func applyAccessibilityLabel(_ label: String) {
        statusItem?.button?.setAccessibilityLabel(label)
        compactEntry?.setAccessibilityLabel(label)
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
        applyTitleText(frames[frameIndex])
        updateAccessibilityLabel(currentText: frames[frameIndex].string)
    }

    private func buildMenu(body: [MenuNode]) -> NSMenu {
        let menu = MenuBuilder.build(body, target: actionTarget)
        // Opt-in searchable panel: a "Search…" row at the top opens a filterable,
        // keyboard-driven view of every item — including those nested in
        // submenus — without disturbing the native menu, its trust row, or the
        // controls footer.
        if filterEnabled {
            // Compact mode nests every plugin's menu in one tree, where a key
            // equivalent set here would ambiguously fire on whichever
            // plugin's item AppKit finds first — strip it there.
            let search = NSMenuItem(title: "Search…", action: #selector(ControlsTarget.search), keyEquivalent: isCompact ? "" : "f")
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

        // Same first-match-wins hazard as the Search row above: no key
        // equivalent on a per-plugin control item once it's nested in
        // compact mode's shared tree.
        let refresh = NSMenuItem(title: "Refresh", action: #selector(ControlsTarget.refresh), keyEquivalent: isCompact ? "" : "r")
        refresh.target = controls
        menu.addItem(refresh)

        if hasSettings {
            let settings = NSMenuItem(title: "Settings…", action: #selector(ControlsTarget.settings), keyEquivalent: isCompact ? "" : ",")
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

        let quit = NSMenuItem(title: "Quit Vee", action: #selector(ControlsTarget.quit), keyEquivalent: isCompact ? "" : "q")
        quit.target = controls
        menu.addItem(quit)
        return menu
    }
}
