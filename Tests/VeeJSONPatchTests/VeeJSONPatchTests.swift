import XCTest
@testable import VeeJSONPatch
import VeeProtocol

/// Wave 0 placeholder so the target builds. Wave 1d worker REPLACES this with
/// the real TDD suite (build plan §4, 10 cases incl. the 1000-case property
/// test apply(diff(a,b),a)==b) — write failing tests first.
final class VeeJSONPatchTests: XCTestCase {
    func testSkeletonBuilds() throws {
        let a: JSONValue = ["x": 1]
        let b: JSONValue = ["x": 2]
        let patch = JSONPatch.diff(a, b)
        XCTAssertEqual(try JSONPatch.apply(patch, to: a), b)
    }
}
