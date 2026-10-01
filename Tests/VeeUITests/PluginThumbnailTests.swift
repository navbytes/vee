import XCTest
import SwiftUI
import AppKit
import VeeCatalog
import VeePluginFormat
@testable import VeeUI

/// The Discover list draws a plugin's screenshot as a fixed-size thumbnail, so
/// a declared image can never change a row's height. `PluginThumbnail` renders
/// every `AsyncImagePhase` at one size (an `.empty`/`.failure` that rendered 0pt
/// used to jump the old card's height mid-scroll), and the row's metadata block
/// reserves at least that height. Mirrors `CategoryChartCardSizeTests`'s
/// `ImageRenderer` measurement pattern.
@MainActor
final class PluginThumbnailTests: XCTestCase {
    /// Stands in for a Discover row's width so `maxWidth: .infinity` has
    /// something concrete to resolve against when rendered off-screen.
    private let rowWidth: CGFloat = 560

    private struct StubFetcher: CatalogFetching {
        func fetchIndex() async throws -> [CatalogEntry] { [] }
        func fetchSource(_ entry: CatalogEntry) async throws -> String { "" }
        func fetchLastUpdated(_ entry: CatalogEntry) async throws -> Date? { nil }
    }

    func testThumbnailRendersEveryPhaseAtTheSameFixedSize() throws {
        let phases: [AsyncImagePhase] = [
            .empty,
            .success(Image(systemName: "photo")),
            .failure(URLError(.badServerResponse))
        ]

        for phase in phases {
            let renderer = ImageRenderer(content: PluginThumbnail(phase: phase, title: "Test", onTapSuccess: {}))
            let size = try XCTUnwrap(renderer.nsImage).size
            XCTAssertEqual(size.width, PluginThumbnail.size.width, accuracy: 0.5, "width for \(phase)")
            XCTAssertEqual(size.height, PluginThumbnail.size.height, accuracy: 0.5, "height for \(phase)")
        }
    }

    /// The invariant the old 120pt grid band broke: a row that declares a
    /// screenshot must render at the same height as one that does not.
    func testRowHeightDoesNotDependOnTheScreenshot() throws {
        let withImage = try renderedRowHeight(declaringImage: true)
        let withoutImage = try renderedRowHeight(declaringImage: false)

        XCTAssertEqual(withImage, withoutImage, accuracy: 0.5,
                       "a row with a screenshot must be the same height as one without")
        XCTAssertGreaterThanOrEqual(withImage, PluginThumbnail.size.height,
                                    "the row must be at least as tall as its thumbnail")
    }

    /// The metadata block reserves a floor, and the screenshot is fixed; as
    /// long as the thumbnail is no taller than that floor, it can never raise a
    /// row's height.
    func testThumbnailFitsWithinTheRowMetadataFloor() {
        XCTAssertLessThanOrEqual(PluginThumbnail.size.height, PluginCatalogRow.metadataMinHeight)
    }

    private func renderedRowHeight(declaringImage: Bool) throws -> CGFloat {
        let entry = CatalogEntry(
            path: "Tools/cpu.10s.sh",
            category: "Tools",
            filename: "cpu.10s.sh",
            rawURL: URL(string: "https://raw.githubusercontent.com/x/y/main/Tools/cpu.10s.sh")!
        )
        let model = PluginBrowserModel(fetcher: StubFetcher(), pluginsDirectory: NSTemporaryDirectory(), onInstalled: {})
        model.entries = [entry]
        if declaringImage {
            var header = HeaderMetadata()
            header.image = "https://raw.githubusercontent.com/x/y/main/Tools/cpu.png"
            model.headers[entry.id] = header
        }
        XCTAssertEqual(model.previewImageURL(for: entry) != nil, declaringImage,
                       "test setup: the model must expose an image only when one is declared")

        let view = PluginCatalogRow(model: model, entry: entry).frame(width: rowWidth)
        return try XCTUnwrap(ImageRenderer(content: view).nsImage).size.height
    }
}
