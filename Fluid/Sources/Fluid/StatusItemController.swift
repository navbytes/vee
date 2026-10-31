#if os(macOS)
import AppKit
import Observation
import SwiftUI
import FluidProtocol

/// A plugin's menu-bar item: draws the `menuBar` tree as the button and opens
/// the `panel` tree in a popover.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    let controller: PluginController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    init(controller: PluginController) {
        self.controller = controller
        super.init()
        statusItem.autosaveName = "fluid." + controller.source.lastPathComponent
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PanelView(controller: controller))
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel(_:))
        }
        observe()
    }

    func remove() {
        popover.close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// Re-draws the button whenever the menu-bar tree or the state changes.
    private func observe() {
        withObservationTracking {
            updateButton()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        var summary = Self.summary(of: controller.menuBar)
        switch controller.state {
        case .failed:
            summary = (controller.name, "exclamationmark.triangle", .critical)
        case .starting where controller.menuBar == nil:
            summary = (controller.name, "hourglass", .secondary)
        default:
            break
        }
        if let symbol = summary.symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: summary.title) {
            image.isTemplate = true
            button.image = image
            button.imagePosition = summary.title.isEmpty ? .imageOnly : .imageLeading
        } else {
            button.image = nil
        }
        let color = summary.role.nsColor
        button.contentTintColor = color
        button.attributedTitle = NSAttributedString(string: summary.title, attributes: color.map { [.foregroundColor: $0] } ?? [:])
    }

    /// What a menu-bar tree boils down to: one title, one symbol, one role.
    static func summary(of node: ViewNode?) -> (title: String, symbol: String?, role: Role) {
        switch node {
        case .label(let title, let symbol, let role)?:
            return (title, symbol, role)
        case .text(let title, _, let role)?:
            return (title, nil, role)
        case .badge(let title, let role)?:
            return (title, nil, role)
        case .stack(_, _, let children)?:
            let parts = children.map { summary(of: $0) }
            let title = parts.map(\.title).filter { !$0.isEmpty }.joined(separator: " ")
            let role = parts.first { $0.role != .primary }?.role ?? .primary
            return (title, parts.compactMap(\.symbol).first, role)
        default:
            return ("", "puzzlepiece.extension", .primary)
        }
    }

    @objc private func togglePanel(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverDidShow(_ notification: Notification) {
        controller.setPanelVisible(true)
    }

    func popoverDidClose(_ notification: Notification) {
        controller.setPanelVisible(false)
    }
}

extension Role {
    /// `nil` means "the system's default for this place".
    var nsColor: NSColor? {
        switch self {
        case .primary: return nil
        case .secondary: return .secondaryLabelColor
        case .accent: return .controlAccentColor
        case .success: return .systemGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }
}
#endif
