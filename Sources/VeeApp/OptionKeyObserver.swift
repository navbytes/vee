import AppKit

/// Feeds the live ⌥ state into a `MenuSearchViewModel`, so the SwiftUI menu
/// surfaces swap `alternate=` pairs the way the AppKit dropdown does natively.
///
/// A local `flagsChanged` monitor only sees events while Vee is active — true
/// whenever the panel or a detached window is actually in use — so attaching
/// also snapshots the current flags (⌥ may already be down when the surface
/// opens), and re-snapshots when the app's activation changes (⌥ may be
/// released while another app is frontmost, an event a local monitor never
/// sees, which would otherwise freeze the surface on the alternates).
///
/// The owner calls `detach()` on the same path that tears down its surface —
/// the panel's dismiss, a window's close eviction — or the monitor leaks,
/// exactly like the panel's existing key monitor would.
@MainActor
final class OptionKeyObserver {
    private var monitor: Any?
    private var activationTokens: [NSObjectProtocol] = []

    func attach(to model: MenuSearchViewModel) {
        detach()
        model.optionHeld = NSEvent.modifierFlags.contains(.option)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak model] event in
            model?.optionHeld = event.modifierFlags.contains(.option)
            return event
        }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            activationTokens.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak model] _ in
                MainActor.assumeIsolated {
                    model?.optionHeld = NSEvent.modifierFlags.contains(.option)
                }
            })
        }
    }

    func detach() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        for token in activationTokens { NotificationCenter.default.removeObserver(token) }
        activationTokens = []
    }
}
