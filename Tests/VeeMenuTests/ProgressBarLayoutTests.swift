import XCTest
import AppKit
@testable import VeeMenu

/// Covers the pure geometry of the inline `progress=` gauge row.
final class ProgressBarLayoutTests: XCTestCase {
    private let layout = ProgressBarLayout(barWidth: 120, barHeight: 6) // insets 20/12, gap 10

    func testTrackIsTrailingAnchoredAndFillIsFraction() {
        let (label, track, fill) = layout.rects(in: CGRect(x: 0, y: 0, width: 260, height: 22), fraction: 0.5)
        XCTAssertEqual(track.minX, 128, accuracy: 0.01)   // 260 - 12 - 120
        XCTAssertEqual(track.width, 120, accuracy: 0.01)
        XCTAssertEqual(track.height, 6, accuracy: 0.01)
        XCTAssertEqual(track.midY, 11, accuracy: 0.01)    // vertically centered
        XCTAssertEqual(fill.width, 60, accuracy: 0.01)    // 120 * 0.5
        XCTAssertEqual(fill.minX, track.minX, accuracy: 0.01)
        XCTAssertEqual(label.minX, 20, accuracy: 0.01)
        XCTAssertEqual(label.width, 98, accuracy: 0.01)   // 128 - 10 - 20
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
        XCTAssertEqual(wide.label.width, 238, accuracy: 0.01) // 268 - 10 - 20
    }

    func testNarrowRowClampsLabelWidthToZero() {
        let tiny = layout.rects(in: CGRect(x: 0, y: 0, width: 130, height: 22), fraction: 0.5)
        XCTAssertEqual(tiny.label.width, 0, accuracy: 0.01) // trackX (~ -2) - gap - inset < 0
    }
}
