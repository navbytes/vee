import AppKit
import SwiftUI
import VeeUI

/// Presents a plugin's inline `sparkline=…` series in a native `NSPopover`
/// hosting a SwiftUI Swift Charts view (`SparklineChartView`). Like
/// `WebViewPresenter`, this lives *outside* the `NSMenu` — the menu that
/// launched it has already closed — so the menu itself stays native and
/// leak-free. Only one popover is shown at a time.
@MainActor
final class PluginPopover: NSObject, NSPopoverDelegate {
    static let shared = PluginPopover()

    private var popover: NSPopover?
    /// A tiny transparent window used only as the popover's positioning anchor,
    /// placed at the mouse location (i.e. under the menu-bar item just clicked).
    /// Retained so ARC doesn't drop the anchor while the popover is on screen.
    private var anchorWindow: NSWindow?

    func show(series: [Double], title: String) {
        dismiss()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 260, height: 150)
        popover.contentViewController = NSHostingController(
            rootView: SparklineChartView(values: series, title: title)
        )
        popover.delegate = self

        let mouse = NSEvent.mouseLocation
        let frame = NSRect(x: mouse.x - 1, y: mouse.y - 1, width: 2, height: 2)
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.orderFront(nil)

        let anchor = NSView(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = anchor

        self.popover = popover
        self.anchorWindow = window

        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func popoverDidClose(_ notification: Notification) {
        dismiss()
    }

    private func dismiss() {
        popover?.close()
        popover = nil
        anchorWindow?.orderOut(nil)
        anchorWindow = nil
    }
}
