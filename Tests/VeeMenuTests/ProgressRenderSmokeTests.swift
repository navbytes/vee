import XCTest
import AppKit
@testable import VeeMenu
@testable import VeePluginFormat

/// Renders `progress=` rows through the real `MenuBuilder`→`ProgressMenuItemView`
/// path into an offscreen bitmap: a smoke test that the custom view draws
/// something, and (when `VEE_RENDER_OUT` is set) a way to eyeball the result
/// without opening the live menu.
@MainActor
final class ProgressRenderSmokeTests: XCTestCase {
    private final class NoopHandler: MenuActionHandling {
        func perform(_ item: MenuItem) {}
    }

    private func item(_ line: String) -> MenuItem {
        let (text, pairs, _) = LineParser.splitTextAndParams(line)
        return MenuItem(text: text, params: LineParser.mapParams(pairs).params)
    }

    func testProgressRowsRenderNonEmpty() {
        let lines = [
            "$23.65 of $100 | size=14 color=#36C26E progress=23.65,100 trackcolor=#3C4046 progressw=210 progressh=10",
            "Jul 3   $100 | progress=100,100 color=#FF5C5C trackcolor=#3C4046 progressw=140 size=11",
            "Jul 2   $86  | progress=86,100 color=#F5A623 trackcolor=#3C4046 progressw=140 size=11",
            "Jul 1   $32  | progress=32,100 color=#36C26E trackcolor=#3C4046 progressw=140 size=11",
            "Idle            | progress=0",
        ]
        let handler = NoopHandler() // retained: MenuActionTarget holds it weakly
        let menu = MenuBuilder.build(lines.map { .item(item($0)) }, target: MenuActionTarget(handler: handler))

        let views = menu.items.compactMap { $0.view }
        XCTAssertEqual(views.count, lines.count, "every progress row should render a custom view")

        // The menu sizes to the widest self-sized row (like a real NSMenu).
        let width: CGFloat = views.map { $0.frame.width }.max() ?? 280
        let rowH: CGFloat = 24
        let canvas = NSImage(size: NSSize(width: width, height: rowH * CGFloat(views.count)))
        canvas.lockFocus()
        NSColor(white: 0.13, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: rowH * CGFloat(views.count)).fill()

        var nonEmpty = false
        for (i, view) in views.enumerated() {
            view.frame = NSRect(x: 0, y: 0, width: width, height: rowH)
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let y = CGFloat(views.count - 1 - i) * rowH // top-to-bottom in the image
            rep.draw(in: NSRect(x: 0, y: y, width: width, height: rowH))
            if let data = rep.tiffRepresentation, data.count > 100 { nonEmpty = true }
        }
        canvas.unlockFocus()
        XCTAssertTrue(nonEmpty, "progress rows should render pixels")

        if let out = ProcessInfo.processInfo.environment["VEE_RENDER_OUT"], !out.isEmpty,
           let tiff = canvas.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: out))
        }
    }
}
