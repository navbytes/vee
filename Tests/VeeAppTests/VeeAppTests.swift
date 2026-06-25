import XCTest
@testable import VeeApp
import VeeProtocol

/// Wave 0 placeholder so the target builds. Wave 3 worker REPLACES this with the
/// real AppCoordinator TDD suite (build plan §4, 5 cases: render-tree→view-model
/// mapping, selection preservation, action dispatch) — write failing tests first.
final class VeeAppTests: XCTestCase {
    func testSkeletonBuilds() {
        _ = AppCoordinator()
        XCTAssertTrue(true)
    }
}
