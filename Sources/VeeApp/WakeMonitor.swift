import AppKit

/// Forces a refresh when the machine wakes from sleep. Plugins silently going
/// stale (or stopping entirely) after sleep/wake is the single most common
/// reliability complaint for xbar and SwiftBar; re-running everything on
/// `didWake` keeps Vee's menu bar current the moment the Mac comes back.
@MainActor
final class WakeMonitor {
    private let center: NotificationCenter
    private let onWake: () -> Void
    private var token: NSObjectProtocol?

    init(center: NotificationCenter = NSWorkspace.shared.notificationCenter, onWake: @escaping () -> Void) {
        self.center = center
        self.onWake = onWake
    }

    func start() {
        // Deliver synchronously on the posting thread (NSWorkspace posts on the
        // main thread), so no cross-thread hop is needed.
        token = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.onWake() }
        }
    }

    func stop() {
        if let token { center.removeObserver(token) }
        token = nil
    }
}
