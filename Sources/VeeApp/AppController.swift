import AppKit
import VeeCore

/// The application delegate. Owns the set of status-item controllers and wires
/// up the app lifecycle. Stage 0 installs one static status item.
@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    private var statusItems: [StatusItemController] = []
    private let log = VeeLog.make("app-controller")

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("Vee launched")
        statusItems.append(StatusItemController())
    }
}
