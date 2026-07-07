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

/// Presents the Spotlight-like search panel for one plugin's (flattened) menu.
/// Lives *outside* the `NSMenu` — the menu that launched it has already closed —
/// so the native menu, its trust row, and its controls footer are untouched;
/// this is an additional surface, not a replacement. Only one panel at a time.
///
/// Selecting a row dispatches through the plugin's existing `MenuActionHandling`,
/// so href / shell / shortcut / refresh and the toggle/slider/sparkline popovers
/// all fire with no new action model.
@MainActor
final class MenuSearchPanel: NSObject {
    static let shared = MenuSearchPanel()

    private var panel: KeyablePanel?
    private var model: MenuSearchViewModel?
    private weak var handler: MenuActionHandling?
    private var keyMonitor: Any?
    private var clickMonitor: Any?

    private static let size = NSSize(width: 440, height: 380)

    /// Opens the panel for `rows`, anchored near the mouse (i.e. under the just-
    /// clicked status item), routing activations to `handler`.
    func present(rows: [FlatRow], pluginName: String, handler: MenuActionHandling) {
        dismiss()
        self.handler = handler

        let model = MenuSearchViewModel(rows: rows)
        self.model = model

        let root = MenuSearchView(
            model: model,
            pluginName: pluginName,
            onActivate: { [weak self] row in self?.activate(row) },
            onClose: { [weak self] in self?.dismiss() }
        )

        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
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
        let handler = self.handler
        dismiss()
        handler?.perform(row.item)
    }

    func dismiss() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
        handler = nil
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
        let size = Self.size
        var x = mouse.x - size.width / 2
        var y = mouse.y - size.height - 6
        x = min(max(visible.minX + 8, x), visible.maxX - size.width - 8)
        y = min(max(visible.minY + 8, y), visible.maxY - size.height - 8)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
    }
}

// MARK: - SwiftUI

/// The panel's content: a focused search field over a scrollable, keyboard-
/// navigable result list with breadcrumbs. Business logic lives in the view
/// model; this view is presentation only.
private struct MenuSearchView: View {
    @ObservedObject var model: MenuSearchViewModel
    let pluginName: String
    let onActivate: (FlatRow) -> Void
    let onClose: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(pluginName)…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($searchFocused)
                    .onSubmit { if let row = model.selectedRow() { onActivate(row) } }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider()

            if model.results.isEmpty {
                Spacer()
                Text("No matches").foregroundStyle(.secondary)
                Spacer()
            } else {
                resultList
            }
        }
        .frame(width: 440, height: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear { searchFocused = true }
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.results.enumerated()), id: \.offset) { index, row in
                        SearchRowView(row: row, selected: index == model.selection)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture { onActivate(row) }
                    }
                }
                .padding(6)
            }
            .onChange(of: model.selection) { _, selection in
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(selection, anchor: .center) }
            }
        }
    }
}

/// One result row: SF Symbol (when the item declares one), the item text, and a
/// dim breadcrumb of its ancestor groups.
private struct SearchRowView: View {
    let row: FlatRow
    let selected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: row.item.params.swiftbar.sfimage ?? "circle.dashed")
                .font(.system(size: 13))
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.item.text)
                    .font(.system(size: 13))
                    .lineLimit(1)
                if !row.breadcrumb.isEmpty {
                    Text(row.breadcrumb)
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.7)) : AnyShapeStyle(.tertiary))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // Surface the plugin's own "currently selected" marker (`checked=true`)
            // so an active choice (e.g. the current context) is visible in the panel.
            if row.item.params.swiftbar.checked == true {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.accentColor))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear))
        )
    }
}
