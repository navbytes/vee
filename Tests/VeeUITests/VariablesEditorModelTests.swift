import XCTest
import VeeCore
import VeePluginFormat
import VeePreferences
@testable import VeeUI

@MainActor
final class VariablesEditorModelTests: XCTestCase {
    private final class FailingSecretStore: SecretStoring, @unchecked Sendable {
        func get(_ account: String) -> String? { nil }
        func set(_ value: String?, for account: String) throws { throw SecretStoreError.operationFailed }
        func deleteAll() {}
    }

    private let declaration = VarDeclaration(
        name: "API_TOKEN", kind: .string, defaultValue: "", summary: "Token", options: [], isSecret: true
    )

    private func group() -> PluginVariableGroup {
        PluginVariableGroup(
            pluginID: PluginID(rawValue: "weather.sh"), pluginName: "Weather", pluginPath: "/tmp/weather.sh",
            declarations: [declaration]
        )
    }

    func testFailedSaveIdentifiesFieldWithoutValueAndKeepsEditForRetry() {
        var shouldFail = true
        var saved = false
        var persisted: [String] = []
        let model = VariablesEditorModel(groups: [group()], secretStore: { _ in InMemorySecretStore() }, persistValue: { _, _, value in
            if shouldFail { throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: "leaked \(value)"]) }
            persisted.append(value)
        }, onSaved: { saved = true })
        model.values["weather.sh"]?["API_TOKEN"] = "top-secret"

        XCTAssertFalse(model.save())
        XCTAssertFalse(saved)
        XCTAssertEqual(model.saveFailures, [.init(pluginName: "Weather", fieldName: "API_TOKEN")])
        XCTAssertEqual(model.values["weather.sh"]?["API_TOKEN"], "top-secret")
        XCTAssertFalse(String(describing: model.saveFailures).contains("top-secret"))

        shouldFail = false
        XCTAssertTrue(model.save())
        XCTAssertTrue(saved)
        XCTAssertEqual(persisted, ["top-secret"])
        XCTAssertEqual(model.saveFailures, [])
    }

    func testProductionPreferencePathReportsSecretStoreFailure() {
        var saved = false
        let model = VariablesEditorModel(groups: [group()], secretStore: { _ in FailingSecretStore() }, onSaved: { saved = true })
        model.values["weather.sh"]?["API_TOKEN"] = "top-secret"

        XCTAssertFalse(model.save())
        XCTAssertFalse(saved)
        XCTAssertEqual(model.saveFailures, [.init(pluginName: "Weather", fieldName: "API_TOKEN")])
        XCTAssertEqual(model.values["weather.sh"]?["API_TOKEN"], "top-secret")
    }

    func testReconcilePreservesOnlyCompatibleDrafts() {
        let model = VariablesEditorModel(groups: [group()], secretStore: { _ in InMemorySecretStore() })
        model.values["weather.sh"]?["API_TOKEN"] = "draft"
        XCTAssertTrue(model.isDirty)

        let added = VarDeclaration(name: "CITY", kind: .string, defaultValue: "HK", summary: "", options: [], isSecret: false)
        model.reconcile(groups: [PluginVariableGroup(
            pluginID: PluginID(rawValue: "weather.sh"), pluginName: "Weather", pluginPath: "/tmp/weather.sh",
            declarations: [declaration, added]
        )])
        XCTAssertEqual(model.values["weather.sh"]?["API_TOKEN"], "draft")
        XCTAssertEqual(model.values["weather.sh"]?["CITY"], "HK")

        let changed = VarDeclaration(name: "API_TOKEN", kind: .boolean, defaultValue: "false", summary: "", options: [], isSecret: false)
        model.reconcile(groups: [PluginVariableGroup(
            pluginID: PluginID(rawValue: "weather.sh"), pluginName: "Weather", pluginPath: "/tmp/weather.sh",
            declarations: [changed]
        )])
        XCTAssertEqual(model.values["weather.sh"]?["API_TOKEN"], "false")
        XCTAssertNil(model.values["weather.sh"]?["CITY"])
    }

    func testReconcilePreservesDirtyFieldButAdoptsExternalChangeForCleanField() throws {
        let path = NSTemporaryDirectory() + "weather-\(UUID().uuidString).sh"
        let city = VarDeclaration(name: "CITY", kind: .string, defaultValue: "", summary: "", options: [], isSecret: false)
        let units = VarDeclaration(name: "UNITS", kind: .string, defaultValue: "", summary: "", options: [], isSecret: false)
        let group = PluginVariableGroup(
            pluginID: PluginID(rawValue: "weather.sh"), pluginName: "Weather", pluginPath: path,
            declarations: [city, units]
        )
        let store = VarStore(pluginPath: path)
        defer { store.delete() }
        try store.set("HK", for: "CITY")
        try store.set("metric", for: "UNITS")
        let model = VariablesEditorModel(groups: [group])
        model.setBufferedValue("draft", pluginID: "weather.sh", field: "CITY")
        try store.set("imperial", for: "UNITS")

        model.reconcile(groups: [group])

        XCTAssertEqual(model.bufferedValue(pluginID: "weather.sh", field: "CITY"), "draft")
        XCTAssertEqual(model.bufferedValue(pluginID: "weather.sh", field: "UNITS"), "imperial")
    }
}
