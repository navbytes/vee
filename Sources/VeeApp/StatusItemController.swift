import AppKit
import VeeCore
import VeePluginFormat
import VeeMenu

/// A small `@objc` target for the per-plugin menu footer (Refresh / Quit).
@MainActor
private final class ControlsTarget: NSObject {
    let onRefresh: () -> Void
    let onSettings: () -> Void
    init(onRefresh: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.onRefresh = onRefresh
        self.onSettings = onSettings
    }
    @objc func refresh() { onRefresh() }
    @objc func settings() { onSettings() }
    @objc func quit() { NSApp.terminate(nil) }
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

    public init(pluginName: String, handler: MenuActionHandling, hasSettings: Bool = false, onRefresh: @escaping () -> Void, onSettings: @escaping () -> Void = {}) {
        self.pluginName = pluginName
        self.hasSettings = hasSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.actionTarget = MenuActionTarget(handler: handler)
        self.controls = ControlsTarget(onRefresh: onRefresh, onSettings: onSettings)
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
    public func renderError(_ message: String) {
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
        appendFooter(to: menu)
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
        appendFooter(to: menu)
        return menu
    }

    private func appendFooter(to menu: NSMenu) {
        menu.addItem(.separator())
        let header = NSMenuItem(title: pluginName, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let refresh = NSMenuItem(title: "Refresh", action: #selector(ControlsTarget.refresh), keyEquivalent: "r")
        refresh.target = controls
        menu.addItem(refresh)

        if hasSettings {
            let settings = NSMenuItem(title: "Settings…", action: #selector(ControlsTarget.settings), keyEquivalent: ",")
            settings.target = controls
            menu.addItem(settings)
        }

        let quit = NSMenuItem(title: "Quit Vee", action: #selector(ControlsTarget.quit), keyEquivalent: "q")
        quit.target = controls
        menu.addItem(quit)
    }
}
