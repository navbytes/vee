import XCTest
import VeeCore
import VeePluginFormat
import VeePreferences
@testable import VeeUI

@MainActor
final class PluginSettingsModelTests: XCTestCase {
    private let declaration = VarDeclaration(
        name: "API_TOKEN", kind: .string, defaultValue: "", summary: "Token", options: [], isSecret: true
    )

    private func preferences() -> PluginPreferences {
        PluginPreferences(
            pluginPath: "/tmp/settings-\(UUID().uuidString).sh",
            pluginID: PluginID(rawValue: "weather.sh"),
            declarations: [declaration],
            secretStore: InMemorySecretStore()
        )
    }

    func testFailedSaveKeepsDraftAndDoesNotNotify() {
        var notified = false
        let model = PluginSettingsModel(
            pluginName: "Weather", prefs: preferences(),
            persistValue: { _, value in throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: value]) },
            onSaved: { notified = true }
        )
        model.values["API_TOKEN"] = "top-secret"

        XCTAssertFalse(model.save())
        XCTAssertFalse(notified)
        XCTAssertTrue(model.isDirty)
        XCTAssertEqual(model.values["API_TOKEN"], "top-secret")
        XCTAssertEqual(model.saveFailures, [.init(pluginName: "Weather", fieldName: "API_TOKEN")])
        XCTAssertFalse(String(describing: model.saveFailures).contains("top-secret"))
    }

    func testSuccessfulSaveClearsDirtyStateAndNotifies() {
        var persisted: [String] = []
        var notified = false
        let model = PluginSettingsModel(
            pluginName: "Weather", prefs: preferences(),
            persistValue: { _, value in persisted.append(value) },
            onSaved: { notified = true }
        )
        model.values["API_TOKEN"] = "saved"

        XCTAssertTrue(model.save())
        XCTAssertEqual(persisted, ["saved"])
        XCTAssertTrue(notified)
        XCTAssertFalse(model.isDirty)
        XCTAssertTrue(model.saveFailures.isEmpty)
    }

    func testRebindPreservesCompatibleDraftAndDropsChangedDeclaration() {
        let model = PluginSettingsModel(pluginName: "Weather", prefs: preferences(), onSaved: {})
        model.values["API_TOKEN"] = "draft"
        model.rebind(prefs: preferences(), features: PluginFeatures(), hotkeyControllable: false, hotkeyEnabled: true, hotkeyCombo: "", hotkeyStatus: .none, hotkeyPresentation: .default, onApplyHotkey: { _, _, _ in .none }, onSaved: {})
        XCTAssertEqual(model.values["API_TOKEN"], "draft")

        let changed = VarDeclaration(name: "API_TOKEN", kind: .boolean, defaultValue: "false", summary: "", options: [], isSecret: false)
        let prefs = PluginPreferences(
            pluginPath: "/tmp/settings-changed.sh", pluginID: PluginID(rawValue: "weather.sh"),
            declarations: [changed], secretStore: InMemorySecretStore()
        )
        model.rebind(prefs: prefs, features: PluginFeatures(), hotkeyControllable: false, hotkeyEnabled: true, hotkeyCombo: "", hotkeyStatus: .none, hotkeyPresentation: .default, onApplyHotkey: { _, _, _ in .none }, onSaved: {})
        XCTAssertEqual(model.values["API_TOKEN"], "false")
    }

    func testRebindPreservesDirtyFieldButAdoptsExternalChangeForCleanField() throws {
        let path = NSTemporaryDirectory() + "settings-\(UUID().uuidString).sh"
        let city = VarDeclaration(name: "CITY", kind: .string, defaultValue: "", summary: "", options: [], isSecret: false)
        let units = VarDeclaration(name: "UNITS", kind: .string, defaultValue: "", summary: "", options: [], isSecret: false)
        let prefs = PluginPreferences(
            pluginPath: path, pluginID: PluginID(rawValue: "weather.sh"), declarations: [city, units],
            secretStore: InMemorySecretStore()
        )
        defer { VarStore(pluginPath: path).delete() }
        try prefs.setValue("HK", for: city)
        try prefs.setValue("metric", for: units)
        let model = PluginSettingsModel(pluginName: "Weather", prefs: prefs, onSaved: {})
        model.values["CITY"] = "draft"
        try prefs.setValue("imperial", for: units)

        model.rebind(prefs: prefs, features: PluginFeatures(), hotkeyControllable: false, hotkeyEnabled: true, hotkeyCombo: "", hotkeyStatus: .none, hotkeyPresentation: .default, onApplyHotkey: { _, _, _ in .none }, onSaved: {})

        XCTAssertEqual(model.values["CITY"], "draft")
        XCTAssertEqual(model.values["UNITS"], "imperial")
    }

    func testRebindUpdatesCleanHotkeyStateButPreservesTypedComboDraft() {
        let model = PluginSettingsModel(
            pluginName: "Weather", prefs: preferences(), hotkeyControllable: true,
            hotkeyCombo: "cmd+a", hotkeyStatus: .active("⌘A"), onSaved: {}
        )
        model.rebind(
            prefs: preferences(), features: PluginFeatures(), hotkeyControllable: true,
            hotkeyEnabled: false, hotkeyCombo: "cmd+b", hotkeyStatus: .disabled,
            hotkeyPresentation: .window, onApplyHotkey: { _, _, _ in .none }, onSaved: {}
        )
        XCTAssertEqual(model.hotkeyCombo, "cmd+b")
        XCTAssertFalse(model.hotkeyEnabled)
        XCTAssertEqual(model.hotkeyPresentation, .window)

        model.hotkeyCombo = "cmd+shift+d"
        XCTAssertTrue(model.isDirty)
        model.rebind(
            prefs: preferences(), features: PluginFeatures(), hotkeyControllable: true,
            hotkeyEnabled: true, hotkeyCombo: "cmd+c", hotkeyStatus: .active("⌘C"),
            hotkeyPresentation: .panel, onApplyHotkey: { _, _, _ in .none }, onSaved: {}
        )
        XCTAssertEqual(model.hotkeyCombo, "cmd+shift+d")
        XCTAssertTrue(model.hotkeyEnabled)
        XCTAssertEqual(model.hotkeyPresentation, .panel)
    }

    func testHotkeyOnlyPluginCanSaveTypedCombo() {
        let prefs = PluginPreferences(
            pluginPath: "/tmp/hotkey-only.sh", pluginID: PluginID(rawValue: "hotkey-only.sh"),
            declarations: [], secretStore: InMemorySecretStore()
        )
        var appliedCombo: String?
        let model = PluginSettingsModel(
            pluginName: "Hotkey", prefs: prefs, hotkeyControllable: true, hotkeyCombo: "cmd+a",
            onApplyHotkey: { _, combo, _ in appliedCombo = combo; return .active(combo) }, onSaved: {}
        )
        model.hotkeyCombo = "cmd+b"

        XCTAssertTrue(model.canSave)
        XCTAssertTrue(model.isDirty)
        XCTAssertTrue(model.save())
        XCTAssertEqual(appliedCombo, "cmd+b")
        XCTAssertFalse(model.isDirty)
    }
}
