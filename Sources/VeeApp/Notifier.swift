import Foundation
import UserNotifications
import VeeCore

/// Posts user notifications (from `swiftbar://notify`). No-ops gracefully when
/// notifications aren't authorized.
@MainActor
enum Notifier {
    nonisolated private static let log = VeeLog.make("notifier")

    /// UNUserNotificationCenter requires a real app bundle; skip when running as
    /// a bare binary (e.g. `swift run vee` during development).
    private static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { Self.log.error("auth failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    static func post(title: String, subtitle: String, body: String) {
        guard isAvailable else {
            Self.log.info("notification skipped (no bundle): \(title, privacy: .public)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "Vee" : title
        if !subtitle.isEmpty { content.subtitle = subtitle }
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Self.log.error("post failed: \(error.localizedDescription, privacy: .public)") }
        }
    }
}
