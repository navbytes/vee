import WidgetKit
import SwiftUI

/// The extension's widget bundle: WidgetKit widgets that surface plugin output
/// on the desktop / Notification Center — a configurable per-plugin status
/// widget and an aggregate health roll-up — plus a Control Center control that
/// refreshes all plugins. The extension is a separate, sandboxed process, so it
/// cannot touch `AppController`; it reads the plugin snapshot the app writes
/// under `~/Library/Application Support/Vee` via a read-only sandbox exception
/// (see `VeeWidgetShared`) and signals refreshes with a Darwin notification.
@main
struct VeeWidgetBundle: WidgetBundle {
    var body: some Widget {
        PluginStatusWidget()
        PluginHealthWidget()
        if #available(macOS 26.0, *) {
            RefreshAllControl()
        }
    }
}
