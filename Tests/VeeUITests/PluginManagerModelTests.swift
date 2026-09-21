import XCTest
import VeePluginFormat
@testable import VeeUI

@MainActor
final class PluginManagerModelTests: XCTestCase {
    private func model(deleteSucceeds: Bool) -> PluginManagerModel {
        PluginManagerModel(
            rows: [.init(id: "weather.sh", name: "Weather", interval: "1m", trust: "", isEnabled: true, hasSettings: false)],
            currentDirectory: "/tmp", launchAtLogin: false,
            onToggleEnabled: { _, _ in }, onReveal: { _ in }, onSettings: { _ in },
            onDelete: { _ in deleteSucceeds }, onLaunchAtLogin: { _ in }, onOpenFolder: {}, onChooseFolder: {}, onRefreshAll: {}
        )
    }

    func testFailedDeleteKeepsRowAndShowsControlledError() {
        let model = model(deleteSucceeds: false)
        model.delete("weather.sh")
        XCTAssertEqual(model.rows.map(\.id), ["weather.sh"])
        XCTAssertEqual(model.deleteError, "Couldn’t move Weather to the Trash. Check file permissions and try again.")
    }

    func testSuccessfulDeleteRemovesRow() {
        let model = model(deleteSucceeds: true)
        model.delete("weather.sh")
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNil(model.deleteError)
    }
}
