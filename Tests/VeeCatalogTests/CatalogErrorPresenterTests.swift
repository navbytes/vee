import XCTest
@testable import VeeCatalog

final class CatalogErrorPresenterTests: XCTestCase {
    func testOfflineIsFriendly() {
        let msg = CatalogErrorPresenter.message(for: URLError(.notConnectedToInternet))
        XCTAssertTrue(msg.lowercased().contains("offline"))
    }

    func testHostFailuresAreTreatedAsOffline() {
        for code: URLError.Code in [.cannotConnectToHost, .networkConnectionLost, .cannotFindHost] {
            XCTAssertTrue(CatalogErrorPresenter.message(for: URLError(code)).lowercased().contains("offline"))
        }
    }

    func testTimeoutMentionsTimeout() {
        let msg = CatalogErrorPresenter.message(for: URLError(.timedOut))
        XCTAssertTrue(msg.lowercased().contains("too long"))
    }

    func testRateLimitIsCalledOut() {
        XCTAssertTrue(CatalogErrorPresenter.message(for: CatalogError.httpStatus(403)).lowercased().contains("rate limit"))
        XCTAssertTrue(CatalogErrorPresenter.message(for: CatalogError.httpStatus(429)).lowercased().contains("rate limit"))
    }

    func testOtherHTTPStatusShowsCode() {
        let msg = CatalogErrorPresenter.message(for: CatalogError.httpStatus(404))
        XCTAssertTrue(msg.contains("404"))
    }

    func testResponseTooLargeIsExplained() {
        let msg = CatalogErrorPresenter.message(for: CatalogError.responseTooLarge(limit: 1024))
        XCTAssertTrue(msg.lowercased().contains("large"))
    }

    func testUnknownErrorFallsBack() {
        struct Weird: Error {}
        XCTAssertTrue(CatalogErrorPresenter.message(for: Weird()).lowercased().contains("couldn't load"))
    }
}
