import XCTest
@testable import VeeApp
import VeePluginFormat

/// [SHOULD-FIX] base64 `image=`/`templateImage=` were invisible in the search
/// panel (only `sfimage=` rendered; everything else fell back to a generic
/// placeholder) — see `SearchRowIcon.decodedImage`, wired into
/// `SearchRowView` in `MenuSearchPanel.swift`. `SymbolImageFactory` itself
/// (the actual base64 decode + cache) is already covered by
/// `VeeMenuTests.SymbolImageCacheTests`; these tests pin down the
/// precedence/wiring this fix adds on top of it.
final class SearchRowIconTests: XCTestCase {
    /// The smallest possible valid PNG: a 1x1 transparent pixel.
    private static let tinyPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="

    func testTemplateImageDecodedAndFlaggedAsTemplate() {
        var params = LineParams()
        params.templateImage = Self.tinyPNGBase64
        let image = SearchRowIcon.decodedImage(for: params)
        XCTAssertNotNil(image, "a declared templateImage= must no longer fall back to the generic placeholder")
        XCTAssertEqual(image?.isTemplate, true)
    }

    func testPlainImageDecodedAndNotFlaggedAsTemplate() {
        var params = LineParams()
        params.image = Self.tinyPNGBase64
        let image = SearchRowIcon.decodedImage(for: params)
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.isTemplate, false)
    }

    func testSfimageTakesPrecedenceOverABase64Image() {
        var params = LineParams()
        params.swiftbar.sfimage = "star"
        params.image = Self.tinyPNGBase64
        XCTAssertNil(SearchRowIcon.decodedImage(for: params), "sfimage= renders via Image(systemName:) instead — this must defer to it")
    }

    func testNeitherDeclaredYieldsNil() {
        XCTAssertNil(SearchRowIcon.decodedImage(for: LineParams()))
    }
}
