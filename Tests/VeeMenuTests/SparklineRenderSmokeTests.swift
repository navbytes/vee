import XCTest
import AppKit
@testable import VeeMenu
@testable import VeePluginFormat

/// Renders `sparkline=` rows through the real `MenuBuilder`→`SparklineMenuItemView`
/// path into an offscreen bitmap: a smoke test that the custom view draws
/// something, mirroring `ProgressRenderSmokeTests`.
@MainActor
final class SparklineRenderSmokeTests: XCTestCase {
    private final class NoopHandler: MenuActionHandling {
        func perform(_ item: MenuItem) {}
    }

    private func item(_ line: String) -> MenuItem {
        let (text, pairs, _) = LineParser.splitTextAndParams(line)
        return MenuItem(text: text, params: LineParser.mapParams(pairs).params)
    }

    func testSparklineRowsRenderNonEmpty() {
        let lines = [
            "Load average | sparkline=0.4,0.6,0.9,1.2,0.8,0.5 color=#36C26E",
            "CPU | sparkline=10,20,15,40,30,60,55,80 color=#F5A623 accessory=leading",
            "Flat | sparkline=5,5,5,5", // range == 0 — must not divide by zero / draw NaN
            "One point | sparkline=42" // < 2 points — flat-baseline fallback path
        ]
        let handler = NoopHandler() // retained: MenuActionTarget holds it weakly
        let menu = MenuBuilder.build(lines.map { .item(item($0)) }, target: MenuActionTarget(handler: handler))

        let views = menu.items.compactMap { $0.view }
        XCTAssertEqual(views.count, lines.count, "every sparkline row should render a custom view")

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
        XCTAssertTrue(nonEmpty, "sparkline rows should render pixels")

        if let out = ProcessInfo.processInfo.environment["VEE_RENDER_OUT"], !out.isEmpty,
           let tiff = canvas.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: out))
        }
    }
}
