import XCTest
@testable import VeeCache
import VeeProtocol

/// Wave 0 placeholder so the target builds. Wave 1b worker REPLACES this with
/// the real TDD suite (build plan §4, 10 cases) — write failing tests first.
final class VeeCacheTests: XCTestCase {
    func testSkeletonBuilds() {
        _ = SWRCache<Int>()
        XCTAssertTrue(true)
    }
}
