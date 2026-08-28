import XCTest
import AppKit
@testable import VeeMenu

/// Covers the pure geometry of the inline `progress=` gauge row.
final class ProgressBarLayoutTests: XCTestCase {
    private let layout = ProgressBarLayout(barWidth: 120, barHeight: 6) // insets 16/12, gap 10

    func testTrackIsTrailingAnchoredAndFillIsFraction() {
        let (label, track, fill) = layout.rects(in: CGRect(x: 0, y: 0, width: 260, height: 22), fraction: 0.5)
        XCTAssertEqual(track.minX, 128, accuracy: 0.01)   // 260 - 12 - 120
        XCTAssertEqual(track.width, 120, accuracy: 0.01)
        XCTAssertEqual(track.height, 6, accuracy: 0.01)
        XCTAssertEqual(track.midY, 11, accuracy: 0.01)    // vertically centered
        XCTAssertEqual(fill.width, 60, accuracy: 0.01)    // 120 * 0.5
        XCTAssertEqual(fill.minX, track.minX, accuracy: 0.01)
        XCTAssertEqual(label.minX, layout.leadingInset, accuracy: 0.01)
        XCTAssertEqual(label.width, 128 - layout.gap - layout.leadingInset, accuracy: 0.01)
    }

    func testFractionClampedIntoBar() {
        let over = layout.rects(in: CGRect(x: 0, y: 0, width: 260, height: 22), fraction: 1.5)
        XCTAssertEqual(over.fill.width, 120, accuracy: 0.01) // clamped to full bar
        let under = layout.rects(in: CGRect(x: 0, y: 0, width: 260, height: 22), fraction: -0.5)
        XCTAssertEqual(under.fill.width, 0, accuracy: 0.01)
    }

    func testTrackStaysTrailingAsWidthGrows() {
        let wide = layout.rects(in: CGRect(x: 0, y: 0, width: 400, height: 22), fraction: 1)
        XCTAssertEqual(wide.track.minX, 268, accuracy: 0.01) // 400 - 12 - 120
        XCTAssertEqual(wide.label.width, 268 - layout.gap - layout.leadingInset, accuracy: 0.01)
    }

    func testNarrowRowClampsLabelWidthToZero() {
        let tiny = layout.rects(in: CGRect(x: 0, y: 0, width: 130, height: 22), fraction: 0.5)
        XCTAssertEqual(tiny.label.width, 0, accuracy: 0.01) // trackX (~ -2) - gap - inset < 0
    }

    // MARK: - accessory=leading

    private let leadingLayout = ProgressBarLayout(barWidth: 120, barHeight: 6, leading: true)

    func testLeadingAnchorsTrackToLeadingEdgeAndLabelFillsRest() {
        let (label, track, fill) = leadingLayout.rects(in: CGRect(x: 0, y: 0, width: 260, height: 22), fraction: 0.5)
        XCTAssertEqual(track.minX, leadingLayout.leadingInset, accuracy: 0.01)
        XCTAssertEqual(track.width, 120, accuracy: 0.01)
        XCTAssertEqual(fill.width, 60, accuracy: 0.01)    // 120 * 0.5, still grows from the track's own origin
        XCTAssertEqual(fill.minX, track.minX, accuracy: 0.01)
        XCTAssertEqual(label.minX, leadingLayout.leadingInset + 120 + 10, accuracy: 0.01) // trackX + barWidth + gap
        XCTAssertEqual(label.width, 260 - 12 - label.minX, accuracy: 0.01) // maxX - trailingInset - labelX
    }

    func testLeadingTrackStaysLeadingAsWidthGrows() {
        let wide = leadingLayout.rects(in: CGRect(x: 0, y: 0, width: 400, height: 22), fraction: 1)
        XCTAssertEqual(wide.track.minX, leadingLayout.leadingInset, accuracy: 0.01) // unchanged — anchored to the leading edge, not the trailing one
        XCTAssertEqual(wide.label.width, 400 - 12 - (leadingLayout.leadingInset + 120 + 10), accuracy: 0.01)
    }

    func testLeadingNarrowRowClampsLabelWidthToZero() {
        let tiny = leadingLayout.rects(in: CGRect(x: 0, y: 0, width: 130, height: 22), fraction: 0.5)
        XCTAssertEqual(tiny.label.width, 0, accuracy: 0.01) // labelX (146) already past maxX - trailingInset (118)
    }

    /// A pin, not coverage: `leadingInset` is a visual calibration against
    /// AppKit's own menu-title inset, so nothing else in the suite would catch
    /// someone "tidying" it to a rounder number. Measured by rendering the same
    /// leading glyph in both kinds of row ("Charge:" in an accessory row against
    /// "Charging" in a plain one): at 20 the accessory row's text landed at
    /// 20.5pt against plain text at 16.5pt — a visible 4pt indent on the one row
    /// in a menu carrying a bar or chart. Re-measure that way before changing it.
    func testLeadingInsetMatchesAppKitMenuTitleInset() {
        XCTAssertEqual(ProgressBarLayout(barWidth: 1, barHeight: 1).leadingInset, 16, accuracy: 0.01)
    }

    func testLeadingDefaultsFalseSoExistingInitCallersAreUnaffected() {
        XCTAssertFalse(layout.leading)
        XCTAssertTrue(leadingLayout.leading)
    }
}
