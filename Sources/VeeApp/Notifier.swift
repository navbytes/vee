import Foundation
import UserNotifications
import VeeCore

/// Posts user notifications (from `swiftbar://notify`). No-ops gracefully when
/// notifications aren't authorized.
@MainActor
enum Notifier {
    nonisolated private static let log = VeeLog.make("notifier")

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { Self.log.error("auth failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    static func post(title: String, subtitle: String, body: String) {
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
