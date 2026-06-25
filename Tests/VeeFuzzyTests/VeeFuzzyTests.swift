import XCTest
@testable import VeeFuzzy
import VeeProtocol

/// Wave 0 placeholder so the target builds. Wave 1a worker REPLACES this with
/// the real TDD suite (build plan §4, 10 cases) — write failing tests first.
final class VeeFuzzyTests: XCTestCase {
    func testSkeletonBuilds() {
        XCTAssertEqual(FuzzyMatcher.match(query: "", in: []).count, 0)
    }
}
