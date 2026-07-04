import AppKit
import VeeApp

/// Thin executable entry point for development (`swift run vee`). The
/// distributable app bundle uses the same `AppController` via the Xcode target.
@main
struct Vee {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let controller = AppController()
        app.delegate = controller
        // `.accessory`: menu-bar-only, no Dock icon or app-switcher entry.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
