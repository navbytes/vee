import XCTest
import AppKit
@testable import VeeMenu
@testable import VeePluginFormat

/// Renders `pie=`/`donut=`/`stackedbar=` rows through the real
/// `MenuBuilder`→`CategoryChartMenuItemView` path into an offscreen bitmap, and
/// covers the slice geometry directly — mirroring `SparklineRenderSmokeTests`.
@MainActor
final class CategoryChartRenderSmokeTests: XCTestCase {
    private final class NoopHandler: MenuActionHandling {
        func perform(_ item: MenuItem) {}
    }

    private func item(_ line: String) -> MenuItem {
        let (text, pairs, _) = LineParser.splitTextAndParams(line)
        return MenuItem(text: text, params: LineParser.mapParams(pairs).params)
    }

    func testChartRowsRenderNonEmpty() {
        let lines = [
            "By category | pie=45,30,25 chartlabels=Docs,Photos,Apps",
            "By volume | donut=512,256,128 chartcolors=blue,teal,orange",
            "Budget | stackedbar=60,25,15 accessory=leading",
            "One slice | pie=1",                       // whole circle — no gap padding
            "Slivers | donut=1000,1,1",                // gap must not swallow a tiny slice
            "With a hole | stackedbar=0,50,50",        // a zero segment draws nothing
            "Folded | pie=1,2,3,4,5,6,7,8,9,10"        // folded into an "Other" tail
        ]
        let handler = NoopHandler() // retained: MenuActionTarget holds it weakly
        let menu = MenuBuilder.build(lines.map { .item(item($0)) }, target: MenuActionTarget(handler: handler))

        let views = menu.items.compactMap { $0.view }
        XCTAssertEqual(views.count, lines.count, "every chart row should render a custom view")

        let width: CGFloat = views.map { $0.frame.width }.max() ?? 280
        let rowH: CGFloat = 30
        let canvas = NSImage(size: NSSize(width: width, height: rowH * CGFloat(views.count)))
        canvas.lockFocus()
        NSColor(white: 0.13, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: rowH * CGFloat(views.count)).fill()

        var nonEmpty = false
        for (i, view) in views.enumerated() {
            view.frame = NSRect(x: 0, y: 0, width: width, height: rowH)
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let y = CGFloat(views.count - 1 - i) * rowH
            rep.draw(in: NSRect(x: 0, y: y, width: width, height: rowH))
            if let data = rep.tiffRepresentation, data.count > 100 { nonEmpty = true }
        }
        canvas.unlockFocus()
        XCTAssertTrue(nonEmpty, "chart rows should render pixels")

        if let out = ProcessInfo.processInfo.environment["VEE_RENDER_OUT"], !out.isEmpty,
           let tiff = canvas.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: out))
        }
    }

    /// A chart row is clickable (it opens the popover), unlike a bare
    /// `progress=` gauge — so `MenuBuilder` must wire an action to it.
    func testChartRowIsActionable() {
        let handler = NoopHandler()
        let menu = MenuBuilder.build(
            [.item(item("Disk | pie=1,2,3"))],
            target: MenuActionTarget(handler: handler)
        )
        XCTAssertNotNil(menu.items.first?.action)
    }

    func testAccessibilityValueDescribesEverySegment() {
        let view = CategoryChartMenuItemView(
            title: NSAttributedString(string: "Disk"),
            chart: ChartParams(kind: .pie, values: [50, 25, 25], labels: ["Docs"])
        )
        XCTAssertEqual(view.accessibilityLabel(), "Disk")
        XCTAssertEqual(view.accessibilityValue() as? String, "Docs 50%, Segment 2 25%, Segment 3 25%")
    }

    // MARK: - Geometry

    func testWedgeStartsAtTheCenterAndAnnularSectorDoesNot() {
        let center = CGPoint(x: 10, y: 10)
        let wedge = CategoryChartMenuItemView.sectorPath(center: center, inner: 0, outer: 8, from: 90, to: 0)
        let ring = CategoryChartMenuItemView.sectorPath(center: center, inner: 4, outer: 8, from: 90, to: 0)
        XCTAssertGreaterThan(wedge.elementCount, 0)
        XCTAssertGreaterThan(ring.elementCount, 0)

        func firstPoint(_ path: NSBezierPath) -> CGPoint {
            var points = [NSPoint](repeating: .zero, count: 3)
            XCTAssertEqual(path.element(at: 0, associatedPoints: &points), .moveTo)
            return points[0]
        }
        // A pie slice is a wedge drawn from the middle; a donut slice starts on
        // the inner radius, which is what leaves the hole.
        XCTAssertEqual(firstPoint(wedge).x, center.x, accuracy: 0.01)
        XCTAssertEqual(firstPoint(wedge).y, center.y, accuracy: 0.01)
        XCTAssertEqual(firstPoint(ring).x, center.x, accuracy: 0.01)
        XCTAssertEqual(firstPoint(ring).y, center.y + 4, accuracy: 0.01)
    }

    func testInvertedSectorIsEmptyRatherThanDrawingBackwards() {
        // Padding can never invert a slice (it is capped at a quarter of the
        // sweep), but a degenerate range must produce nothing, not a full circle.
        let path = CategoryChartMenuItemView.sectorPath(
            center: .zero, inner: 0, outer: 8, from: 10, to: 20
        )
        XCTAssertEqual(path.elementCount, 0)
    }

    func testCircularAndBarChartsTakeDifferentAccessorySlots() {
        XCTAssertEqual(
            CategoryChartMenuItemView.accessorySize(for: .pie),
            CategoryChartMenuItemView.accessorySize(for: .donut)
        )
        let bar = CategoryChartMenuItemView.accessorySize(for: .stackedBar)
        XCTAssertGreaterThan(bar.width, bar.height, "a stacked bar is wide, not square")
    }
}
