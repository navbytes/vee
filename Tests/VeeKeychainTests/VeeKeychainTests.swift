import XCTest
@testable import VeeKeychain
import VeeProtocol

/// Wave 0 placeholder so the target builds. Wave 1c worker REPLACES this with
/// the real TDD suite (build plan §4, 8 cases) — write failing tests first.
final class VeeKeychainTests: XCTestCase {
    func testSkeletonBuilds() throws {
        let store = InMemorySecretStore()
        XCTAssertNil(try store.get(pluginId: "com.vee.x", namespace: "default", account: "a"))
    }
}
