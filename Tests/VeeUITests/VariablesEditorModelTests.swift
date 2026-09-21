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
}
