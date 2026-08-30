import XCTest
import SwiftUI
import AppKit
@testable import VeeUI

/// `PluginCard.preview` only rendered its `AsyncImage`'s `.success` phase —
/// `.empty`/`.failure` drew 0pt, so a card with a declared screenshot grew
/// underneath the cursor mid-scroll the moment the image finished loading.
/// `PluginPreviewPhaseView` is the fix: every phase reserves the same height.
/// Mirrors `CategoryChartCardSizeTests`'s `ImageRenderer` measurement pattern.
@MainActor
final class PluginPreviewPhaseViewTests: XCTestCase {
    /// Stands in for a Discover grid column (300–460pt, see
    /// `DiscoverContentView.gridColumns`) so `maxWidth: .infinity` has
    /// something concrete to resolve against when rendered off-screen.
    private let cardWidth: CGFloat = 320

    private func renderedHeight(_ phase: AsyncImagePhase) throws -> CGFloat {
        let view = PluginPreviewPhaseView(phase: phase, title: "Test", onTapSuccess: {})
            .frame(width: cardWidth)
        let renderer = ImageRenderer(content: view)
        return try XCTUnwrap(renderer.nsImage).size.height
    }

    func testEveryPhaseRendersAtTheSameFixedHeight() throws {
        let empty = AsyncImagePhase.empty
        let success = AsyncImagePhase.success(Image(systemName: "photo"))
        let failure = AsyncImagePhase.failure(URLError(.badServerResponse))

        let heights = try [empty, success, failure].map { try renderedHeight($0) }

        XCTAssertEqual(
            Set(heights.map { $0.rounded() }), [PluginPreviewPhaseView.height.rounded()],
            "every phase must reserve the same height — got \(heights)"
        )
    }
}
