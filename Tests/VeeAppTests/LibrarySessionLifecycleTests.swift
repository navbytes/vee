import XCTest
import VeePreferences
@testable import VeeApp
import VeeUI

@MainActor
final class LibrarySessionLifecycleTests: XCTestCase {
    private func tempDir() throws -> String {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("vee-library-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    @discardableResult
    private func writePlugin(_ name: String, to directory: String, variable: String = "CITY") throws -> String {
        let path = (directory as NSString).appendingPathComponent(name)
        let source = "#!/bin/bash\n# <vee.surface>widget</vee.surface>\n# <xbar.var>string(\(variable)=\"HK\"): City</xbar.var>\necho hi\n"
        try source.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func preferences() -> AppPreferences {
        AppPreferences(defaults: UserDefaults(suiteName: "vee-library-\(UUID().uuidString)")!)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for Library reconciliation")
    }

    func testRoutesReuseSessionAndPreserveVariablesDraft() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        setenv("VEE_PLUGINS_DIR", dir, 1)
        defer { unsetenv("VEE_PLUGINS_DIR") }
        try writePlugin("weather.sh", to: dir)
        let controller = AppController(preferences: preferences())
        let model = controller.libraryModel(section: .variables)
        model.variables.setBufferedValue("draft", pluginID: "weather.sh", field: "CITY")

        XCTAssertTrue(controller.libraryModel(section: .installed) === model)
        XCTAssertTrue(controller.libraryModel(section: .discover) === model)
        XCTAssertTrue(controller.libraryModel(section: .general) === model)
        XCTAssertEqual(model.variables.bufferedValue(pluginID: "weather.sh", field: "CITY"), "draft")
    }

    func testReloadReconcilesInstalledAndVariablesWithoutLosingCompatibleDraft() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        setenv("VEE_PLUGINS_DIR", dir, 1)
        defer { unsetenv("VEE_PLUGINS_DIR") }
        try writePlugin("weather.sh", to: dir)
        let controller = AppController(preferences: preferences())
        let model = controller.libraryModel(section: .variables)
        controller.reload()
        try await waitUntil { model.manager.rows.count == 1 }
        model.variables.setBufferedValue("draft", pluginID: "weather.sh", field: "CITY")

        try writePlugin("clock.sh", to: dir, variable: "ZONE")
        controller.reload()
        try await waitUntil { model.manager.rows.count == 2 && model.variables.groups.count == 2 }

        XCTAssertEqual(model.variables.bufferedValue(pluginID: "weather.sh", field: "CITY"), "draft")
        XCTAssertNotNil(model.variables.bufferedValue(pluginID: "clock.sh", field: "ZONE"))
    }

    func testFolderSwitchCancelKeepsDraftAndConfirmRebindsAllDirectoryModels() throws {
        let first = try tempDir()
        let second = try tempDir()
        defer {
            try? FileManager.default.removeItem(atPath: first)
            try? FileManager.default.removeItem(atPath: second)
        }
        setenv("VEE_PLUGINS_DIR", first, 1)
        defer { unsetenv("VEE_PLUGINS_DIR") }
        try writePlugin("first.sh", to: first)
        try writePlugin("second.sh", to: second)
        let controller = AppController(preferences: preferences())
        let model = controller.libraryModel(section: .variables)
        model.variables.setBufferedValue("draft", pluginID: "first.sh", field: "CITY")

        XCTAssertFalse(controller.setPluginsDirectory(second, confirmDiscard: { false }))
        XCTAssertEqual(model.general.currentDirectory, first)
        XCTAssertEqual(model.browser.installationDirectory, first)
        XCTAssertEqual(model.variables.bufferedValue(pluginID: "first.sh", field: "CITY"), "draft")

        XCTAssertTrue(controller.setPluginsDirectory(second, confirmDiscard: { true }))
        XCTAssertEqual(model.general.currentDirectory, second)
        XCTAssertEqual(model.manager.currentDirectory, second)
        XCTAssertEqual(model.browser.installationDirectory, second)
        XCTAssertEqual(model.variables.groups.map(\.id), ["second.sh"])
    }

    func testFolderSwitchAlsoGatesDirtyPluginSettings() throws {
        let first = try tempDir()
        let second = try tempDir()
        defer {
            try? FileManager.default.removeItem(atPath: first)
            try? FileManager.default.removeItem(atPath: second)
        }
        setenv("VEE_PLUGINS_DIR", first, 1)
        defer { unsetenv("VEE_PLUGINS_DIR") }
        try writePlugin("first.sh", to: first)
        try writePlugin("second.sh", to: second)
        let controller = AppController(preferences: preferences())
        controller.reload()
        let library = controller.libraryModel(section: .installed)
        let settings = try XCTUnwrap(library.pluginDetail("first.sh")?.settings)
        settings.values["CITY"] = "draft"

        XCTAssertFalse(controller.setPluginsDirectory(second, confirmDiscard: { false }))
        XCTAssertEqual(library.general.currentDirectory, first)
        XCTAssertEqual(settings.values["CITY"], "draft")

        XCTAssertTrue(controller.setPluginsDirectory(second, confirmDiscard: { true }))
        XCTAssertEqual(library.general.currentDirectory, second)
        XCTAssertNil(library.pluginDetail("first.sh"))
    }
}
