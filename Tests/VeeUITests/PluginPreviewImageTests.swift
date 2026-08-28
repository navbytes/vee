import XCTest
import VeeCatalog
import VeePluginFormat
@testable import VeeUI

/// `<xbar.image>` has been parsed and documented as a preview image URL since
/// before this test existed, and read by nothing. Wiring it into the Discover
/// card is what makes the documentation true — but the card is drawn for
/// plugins nobody has chosen, so where the image is *fetched from* is the part
/// worth pinning down.
@MainActor
final class PluginPreviewImageTests: XCTestCase {
    private struct StubFetcher: CatalogFetching {
        func fetchIndex() async throws -> [CatalogEntry] { [] }
        func fetchSource(_ entry: CatalogEntry) async throws -> String { "" }
        func fetchLastUpdated(_ entry: CatalogEntry) async throws -> Date? { nil }
    }

    private func entry(raw: String = "https://raw.githubusercontent.com/x/y/main/Tools/cpu.10s.sh") -> CatalogEntry {
        CatalogEntry(
            path: "Tools/cpu.10s.sh",
            category: "Tools",
            filename: "cpu.10s.sh",
            rawURL: URL(string: raw)!
        )
    }

    private func model(_ e: CatalogEntry, image: String?) -> PluginBrowserModel {
        let m = PluginBrowserModel(fetcher: StubFetcher(), pluginsDirectory: NSTemporaryDirectory(), onInstalled: {})
        m.entries = [e]
        var header = HeaderMetadata()
        header.image = image
        m.headers[e.id] = header
        return m
    }

    func testImageOnTheSameHostAsTheSourceIsUsed() {
        let e = entry()
        let m = model(e, image: "https://raw.githubusercontent.com/x/y/main/Tools/cpu.png")
        XCTAssertEqual(m.previewImageURL(for: e)?.absoluteString,
                       "https://raw.githubusercontent.com/x/y/main/Tools/cpu.png")
    }

    /// The card loads as soon as it scrolls into view, for a plugin the user has
    /// not chosen. An off-host image would make browsing the catalog announce
    /// itself to the author's own server.
    func testImageOnADifferentHostIsRefused() {
        let e = entry()
        XCTAssertNil(model(e, image: "https://tracker.example.com/pixel.png").previewImageURL(for: e))
        XCTAssertNil(model(e, image: "https://raw.githubusercontent.com.evil.example/x.png").previewImageURL(for: e),
                     "a host that merely starts with the real one is a different host")
    }

    func testNonWebSchemesAreRefused() {
        let e = entry()
        XCTAssertNil(model(e, image: "file:///etc/passwd").previewImageURL(for: e))
        XCTAssertNil(model(e, image: "data:image/png;base64,AAAA").previewImageURL(for: e))
        XCTAssertNil(model(e, image: "javascript:alert(1)").previewImageURL(for: e))
    }

    func testAbsentOrEmptyDeclarationIsNil() {
        let e = entry()
        XCTAssertNil(model(e, image: nil).previewImageURL(for: e))
        XCTAssertNil(model(e, image: "   ").previewImageURL(for: e))
        XCTAssertNil(model(e, image: "not a url at all ://").previewImageURL(for: e))
    }

    /// Host comparison is case-insensitive — hostnames are.
    func testHostMatchIsCaseInsensitive() {
        let e = entry(raw: "https://RAW.githubusercontent.com/x/y/main/cpu.10s.sh")
        let m = model(e, image: "https://raw.GITHUBUSERCONTENT.com/x/y/main/cpu.png")
        XCTAssertNotNil(m.previewImageURL(for: e))
    }

    /// A card whose header hasn't been fetched yet must not guess.
    func testNoHeaderYetMeansNoImage() {
        let e = entry()
        let m = PluginBrowserModel(fetcher: StubFetcher(), pluginsDirectory: NSTemporaryDirectory(), onInstalled: {})
        m.entries = [e]
        XCTAssertNil(m.previewImageURL(for: e))
    }
}
