#if canImport(AppIntents)
import AppIntents

/// Exposes Vee's core actions to Shortcuts and Spotlight via App Intents, so
/// users can automate the menu bar (e.g. "Refresh all Vee plugins" as a
/// Shortcut, a Spotlight action, or a Focus/automation trigger) — something
/// neither xbar nor SwiftBar offers first-class.

@available(macOS 13.0, *)
struct RefreshAllPluginsIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh All Plugins"
    static let description = IntentDescription("Re-runs every enabled Vee plugin.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppController.shared?.intentRefreshAll()
        return .result()
    }
}

@available(macOS 13.0, *)
struct RefreshPluginIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Plugin"
    static let description = IntentDescription("Re-runs one Vee plugin by its file name (e.g. cpu.5s.sh).")

    @Parameter(title: "Plugin name")
    var name: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let matched = AppController.shared?.intentRefresh(name: name) ?? false
        return .result(value: matched)
    }
}

@available(macOS 13.0, *)
struct SetPluginEnabledIntent: AppIntent {
    static let title: LocalizedStringResource = "Enable or Disable Plugin"
    static let description = IntentDescription("Turns a Vee plugin on or off by its file name.")

    @Parameter(title: "Plugin name")
    var name: String

    @Parameter(title: "Enabled", default: true)
    var enabled: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        AppController.shared?.intentSetEnabled(enabled, name: name)
        return .result()
    }
}

@available(macOS 13.0, *)
struct VeeAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RefreshAllPluginsIntent(),
            phrases: ["Refresh all \(.applicationName) plugins"],
            shortTitle: "Refresh All Plugins",
            systemImageName: "arrow.clockwise"
        )
    }
}
#endif
