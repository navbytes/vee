import AppKit
import Foundation
import UserNotifications
import VeeCore

/// Posts user notifications (from `swiftbar://notify`). No-ops gracefully when
/// notifications aren't authorized.
@MainActor
enum Notifier {
    nonisolated private static let log = VeeLog.make("notifier")

    /// Retained delegate that opens a notification's `href` when it is clicked.
    /// `UNUserNotificationCenter.delegate` is weak, so this must outlive setup.
    private static let delegate = NotifierDelegate()

    /// UNUserNotificationCenter requires a real app bundle; skip when running as
    /// a bare binary (e.g. `swift run vee` during development).
    private static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().delegate = delegate
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { Self.log.error("auth failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    static func post(title: String, subtitle: String, body: String, href: URL? = nil) {
        guard isAvailable else {
            Self.log.info("notification skipped (no bundle): \(title, privacy: .public)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "Vee" : title
        if !subtitle.isEmpty { content.subtitle = subtitle }
        content.body = body
        // Carry the click-through URL so the delegate can open it on tap.
        if let href { content.userInfo[NotifierDelegate.hrefKey] = href.absoluteString }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Self.log.error("post failed: \(error.localizedDescription, privacy: .public)") }
        }
    }
}

/// Handles notification interaction: clicking a notification with an `href`
/// opens that URL, matching SwiftBar's `notify?href=` behavior.
private final class NotifierDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let hrefKey = "vee.href"

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let string = response.notification.request.content.userInfo[Self.hrefKey] as? String,
           let url = URL(string: string) {
            Task { @MainActor in NSWorkspace.shared.open(url) }
        }
        completionHandler()
    }

    // Still show banners while Vee is frontmost (e.g. a manager window is open).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
