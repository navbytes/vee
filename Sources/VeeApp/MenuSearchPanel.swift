import AppKit
import SwiftUI
import VeeMenu
import VeePluginFormat
import VeeSearch

/// A borderless panel that can still become key — required so its text field
/// receives keystrokes even though Vee is an accessory (LSUIElement) app that
/// isn't the active app when a menu-bar item is clicked. A plain borderless
/// `NSWindow`/`NSPanel` returns `false` from `canBecomeKey`.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Presents the Spotlight-like search panel over a (flattened) menu — either
/// one plugin's own, or every enabled plugin's merged together. Lives *outside*
/// the `NSMenu` — the menu that launched it has already closed — so the native
/// menu, its trust row, and its controls footer are untouched; this is an
/// additional surface, not a replacement. Only one panel at a time.
///
/// Selecting a row runs `activate`, which the caller wires to dispatch through
/// the right plugin's `MenuActionHandling` — so href / shell / shortcut /
/// refresh and the toggle/slider/sparkline popovers all fire with no new
/// action model. A single-plugin caller closes over that one handler; the
/// cross-plugin aggregator closes over a per-row lookup so a row from plugin A
/// never fires through plugin B's handler.
@MainActor
final class MenuSearchPanel: NSObject {
    static let shared = MenuSearchPanel()

    private var panel: KeyablePanel?
    private var model: MenuSearchViewModel?
    private var onActivateRow: ((FlatRow) -> Void)?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    /// Restored on dismiss so row actions (e.g. a clipboard plugin's simulated
    /// ⌘V) land in the app the user invoked the panel from, not in Vee itself.
    private var frontmostRestorer = FrontmostAppRestorer()

    /// The transient panel's fixed content size. Not private: its own SwiftUI
    /// wrapper below applies it, so the number stays declared once.
    static let contentSize = NSSize(width: 440, height: 380)

    /// Opens the panel for `entries`, anchored near the mouse (i.e. under the
    /// just-clicked status item), routing activations through `activate`.
    /// `entries` carries the full panel-visible structure (rows, section
    /// headers, separators); only `.action` rows are ever selectable/
    /// activatable, so `activate` still deals only in `FlatRow`.
    /// `keepOpen`, when supplied, adds the control that promotes this panel into
    /// a detached window. Passing `nil` suppresses it — which is what the
    /// cross-plugin "Search All Plugins" panel does, since there is no single
    /// plugin for such a window to watch.
    func present(
        entries: [SearchEntry],
        pluginName: String,
        keepOpen: (() -> Void)? = nil,
        activate: @escaping (FlatRow) -> Void
    ) {
        dismiss()
        self.onActivateRow = activate
        // Capture BEFORE self-activating below — after that call, Vee itself
        // would be frontmost and we'd have nothing to restore.
        frontmostRestorer.capture(NSWorkspace.shared.frontmostApplication)

        let model = MenuSearchViewModel(entries: entries)
        self.model = model

        let root = MenuSearchView(
            model: model,
            pluginName: pluginName,
            onActivate: { [weak self] row in self?.activate(row) },
            onKeepOpen: keepOpen.map { promote in
                { [weak self] in
                    // Close first: leaving the panel up behind its own window
                    // would show the same plugin twice.
                    self?.dismiss()
                    promote()
                }
            }
        )

        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = NSHostingController(rootView: root)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .ignoresCycle]
        position(panel)

        self.panel = panel
        installMonitors()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Runs the item's action, then closes. Order matters: dismiss first so that
    /// if the action opens its own popover (toggle/slider/sparkline) the panel
    /// isn't stealing key back from it.
    private func activate(_ row: FlatRow) {
        let onActivateRow = self.onActivateRow
        dismiss()
        onActivateRow?(row)
    }

    func dismiss() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
        onActivateRow = nil
        // Hand focus back to whatever the user was in before the panel stole
        // activation. Runs on every dismissal path — row selection, Esc, and
        // outside-click alike — not just the row-activation path, so a
        // cancelled search doesn't leave Vee sitting active either.
        frontmostRestorer.restore()
    }

    // MARK: - Keyboard & outside-click

    private func installMonitors() {
        // Keyboard nav while the panel is key: arrows move the highlight, Return
        // activates, Esc closes. Everything else passes through to the text field.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, let model = self.model else { return event }
            switch event.keyCode {
            case 125: model.moveDown(); return nil          // ↓
            case 126: model.moveUp(); return nil            // ↑
            case 36, 76:                                    // Return / Enter
                if let row = model.selectedRow() { self.activate(row) }
                return nil
            case 53: self.dismiss(); return nil             // Esc
            default: return event
            }
        }
        // A click anywhere outside our app (menu bar, another window, the desktop)
        // dismisses. Clicks inside the panel are delivered locally, not here.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    // MARK: - Positioning

    /// Anchors the panel just below the mouse location, horizontally centered on
    /// it, clamped to the visible frame of whichever screen holds the cursor.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = Self.contentSize
        var x = mouse.x - size.width / 2
        var y = mouse.y - size.height - 6
        x = min(max(visible.minX + 8, x), visible.maxX - size.width - 8)
        y = min(max(visible.minY + 8, y), visible.maxY - size.height - 8)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
    }
}

// MARK: - The transient panel's presentation

/// Wraps the shared content in the panel's own chrome: a fixed-size Liquid Glass
/// card. The window presentation applies none of this, which is the whole reason
/// the chrome lives here rather than in `MenuSearchContentView`.
private struct MenuSearchView: View {
    @ObservedObject var model: MenuSearchViewModel
    let pluginName: String
    let onActivate: (FlatRow) -> Void
    let onKeepOpen: (() -> Void)?

    var body: some View {
        MenuSearchContentView(model: model, pluginName: pluginName, onActivate: onActivate)
            .frame(width: MenuSearchPanel.contentSize.width, height: MenuSearchPanel.contentSize.height)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
            // Overlaid on the chrome rather than placed in the content, so the
            // shared content view stays unaware there is anything to promote to
            // — and so the button is its own VoiceOver element rather than
            // being folded into the search field's row.
            .overlay(alignment: .topTrailing) {
                if let onKeepOpen { KeepOpenButton(action: onKeepOpen) }
            }
    }
}

/// Promotes the transient panel into a window that can be left on the desktop.
private struct KeepOpenButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "macwindow.on.rectangle")
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(10)
        .help("Keep open in a window")
        .accessibilityLabel("Keep open in a window")
    }
}
