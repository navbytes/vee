import XCTest
@testable import VeeApp

@MainActor
final class LoginItemStateSyncTests: XCTestCase {
    func testLibraryModelsShareActualLoginItemResultWithoutSystemMutation() {
        var actual = false
        var shouldFail = true
        let controller = AppController(
            loginItemIsEnabled: { actual },
            setLoginItemEnabled: { requested in
                if !shouldFail { actual = requested }
                return actual
            }
        )
        let library = controller.makeLibraryModel(section: .general)

        library.general.onLaunchAtLogin(true)
        XCTAssertFalse(library.general.launchAtLogin)
        XCTAssertFalse(library.manager.launchAtLogin)
        XCTAssertNotNil(library.general.loginItemError)
        XCTAssertNotNil(library.manager.loginItemError)

        shouldFail = false
        library.manager.onLaunchAtLogin(true)
        XCTAssertTrue(library.general.launchAtLogin)
        XCTAssertTrue(library.manager.launchAtLogin)
        XCTAssertNil(library.general.loginItemError)
        XCTAssertNil(library.manager.loginItemError)
    }
}
