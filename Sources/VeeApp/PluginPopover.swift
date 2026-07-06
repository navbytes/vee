import AppKit
import SwiftUI
import VeePluginFormat
import VeeUI

/// Presents a plugin's native Liquid Glass `NSPopover` — either a read-only
/// `sparkline=…` chart (`SparklineChartView`) or an interactive `toggle=`/
/// `slider=` control (`PluginControlView`). Like `WebViewPresenter`, this lives
/// *outside* the `NSMenu` — the menu that launched it has already closed — so
/// the menu itself stays native and leak-free. Only one popover is shown at a
/// time.
@MainActor
final class PluginPopover: NSObject, NSPopoverDelegate {
    static let shared = PluginPopover()

    private var popover: NSPopover?
    /// A tiny transparent window used only as the popover's positioning anchor,
    /// placed at the mouse location (i.e. under the menu-bar item just clicked).
    /// Retained so ARC doesn't drop the anchor while the popover is on screen.
    private var anchorWindow: NSWindow?

    /// Shows an inline `sparkline=…` series as a Swift Charts popover.
    func show(series: [Double], title: String) {
        present(size: NSSize(width: 260, height: 150)) {
            NSHostingController(rootView: SparklineChartView(values: series, title: title))
        }
    }

    /// Shows an interactive `toggle=`/`slider=` control. `onCommit` fires with
    /// the settled numeric value each time the user changes the control.
    func show(control: PluginControl, title: String, onCommit: @escaping @MainActor (Double) -> Void) {
        present(size: NSSize(width: 260, height: 130)) {
            NSHostingController(
                rootView: PluginControlView(control: control, title: title, onCommit: onCommit)
            )
        }
    }

    /// Builds the transparent mouse-anchored window and shows `popover` from it.
    /// Shared by every popover kind so positioning/leak behavior stays identical.
    private func present(size: NSSize, makeContent: () -> NSViewController) {
        dismiss()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = size
        popover.contentViewController = makeContent()
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
