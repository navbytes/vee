import AppKit
import SwiftUI
@testable import VeeApp
import VeePluginFormat
import VeeSearch
import XCTest

/// Where a window row's content starts. A plugin's hero gauge is a row with a
/// graphic and *no text* (`" | progress=… progressw=full"`); it has to begin on
/// the same vertical line as the text rows around it. It did not: the row stack
/// paid its uniform spacing on both sides of the zero-width title, insetting
/// every graphic-only row by 18pt.
///
/// Asserted by rendering the real view and reading the pixels, because the
/// defect is pure layout — no value in the model is wrong, and SwiftUI exposes
/// no child frames to inspect.
@MainActor
final class GraphicRowLeftEdgeTests: XCTestCase {
    func testGraphicOnlyRowStartsWhereTextRowsDo() throws {
        let output = """
        Text row | color=#ff0000
         | progress=1,1 progressw=full progressh=10 color=#ff0000
        """
        let model = MenuSearchViewModel(nodes: MenuTree.build(OutputParser.parse("t\n---\n" + output).body, surface: .search))
        let host = NSHostingView(rootView: MenuSearchContentView(model: model, pluginName: "p", onActivate: { _ in }))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 160)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)

        // Both rows draw in the plugin's red, so "where does the row's content
        // start" is the leftmost red pixel in the row's band — taken per band
        // rather than per scanline, since a glyph's or a capsule's own outline
        // starts further right on some of its lines.
        var bands: [(y: Int, x: Int)] = []
        for y in 0..<rep.pixelsHigh {
            guard let x = (0..<rep.pixelsWide).first(where: { rep.colorAt(x: $0, y: y).map(Self.isPluginRed) ?? false }) else { continue }
            if let last = bands.last, last.y == y - 1 {
                bands[bands.count - 1] = (y, Swift.min(last.x, x))
            } else {
                bands.append((y, x))
            }
        }
        XCTAssertEqual(bands.count, 2, "expected one band per row, got \(bands.count)")
        let text = try XCTUnwrap(bands.first?.x)
        let graphic = try XCTUnwrap(bands.last?.x)
        // A couple of pixels of slack for the glyph's own left side bearing —
        // the bug this guards was a whole 18pt column.
        XCTAssertLessThanOrEqual(abs(text - graphic), 4, "text row starts at \(text)px, graphic-only row at \(graphic)px")
    }

    private static func isPluginRed(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.sRGB) else { return false }
        return rgb.redComponent > 0.6 && rgb.greenComponent < 0.4 && rgb.blueComponent < 0.4 && rgb.alphaComponent > 0.5
    }
}
