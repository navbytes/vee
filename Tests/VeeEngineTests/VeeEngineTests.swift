import XCTest
@testable import VeeEngine
import VeeProtocol

/// Wave 0 placeholder so the target builds. Wave 2a worker REPLACES this with
/// the real TDD suite (build plan §4, 11 cases incl. microtask ordering and
/// no-leak-after-reload) — write failing tests first.
final class VeeEngineTests: XCTestCase {
    func testSkeletonBuilds() {
        _ = PluginHost()
        XCTAssertTrue(true)
    }
}
