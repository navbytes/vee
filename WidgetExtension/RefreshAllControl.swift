import WidgetKit
import SwiftUI
import AppIntents
import VeeWidgetShared

/// A Control Center control that refreshes every Vee plugin. Because the control
/// runs in the extension (not the app), it signals an already-running Vee with a
/// Darwin notification, and sets `openAppWhenRun` so a closed Vee is launched —
/// which itself refreshes every plugin on startup, covering the cold-start case
/// without needing a shared request file.
@available(macOS 26.0, *)
struct RefreshAllControl: ControlWidget {
    static let kind = "com.vee.app.RefreshAllControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: RefreshAllControlIntent()) {
                Label("Refresh Vee", systemImage: "arrow.clockwise")
            }
        }
        .displayName("Refresh Vee Plugins")
        .description("Re-runs every enabled Vee plugin.")
    }
}

/// Intent backing the control button. Kept in the extension; it never touches
/// `AppController` (a different process) — it only signals a refresh.
struct RefreshAllControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh All Vee Plugins"
    static let description = IntentDescription("Re-runs every enabled Vee plugin from Control Center.")
    /// Launch Vee if it isn't already running so the request is serviced.
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        // Nudge a running Vee to refresh immediately. A closed Vee is launched by
        // openAppWhenRun and refreshes on startup, so no persisted flag is needed.
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(rawValue: VeeWidgetSharing.refreshRequestNotification as CFString),
            nil,
            nil,
            true
        )
        return .result()
    }
}
