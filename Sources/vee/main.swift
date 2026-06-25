import AppKit
import VeeApp
import VeeEngine
import VeeServices
import VeeProtocol

// Thin executable entrypoint — NSApplication bootstrap ONLY. No logic, no
// branching, no parsing: instantiate the real seam adapters, wire them into an
// `AppCoordinator`, and start the run loop. Every decision lives in `VeeApp`
// (the tested library); the seam adapters are logic-free translators.
//
// `main.swift` runs on the main thread, so the AppKit (`@MainActor`) seam
// construction + wiring is done inside `MainActor.assumeIsolated` — the run loop
// owns the main actor from here on.
MainActor.assumeIsolated {
    // The shared in-memory transport: the host writes `plugin.render` toward the
    // launcher; the coordinator (peer) reads it and sends host→plugin frames
    // back. (A real fd/DispatchIO transport swaps in here later untouched.)
    let loopback = LoopbackTransport()

    // The JavaScriptCore plugin host (drives lifecycle; emits renders over `loopback`).
    let host = PluginHost(
        transport: loopback,
        clock: DispatchClock(),
        httpClient: URLSessionHTTPClient(),
        fileWatcher: NoopFileWatcher(),
        bundler: StaticBundler(source: ""))

    // The launcher coordinator, attached to the launcher half of the transport.
    let coordinator = AppCoordinator(
        pluginId: "com.vee.launcher",
        transport: LoopbackCoordinatorTransport(loopback),
        host: host)

    // Real AppKit seams (NSPanel launcher window + NSStatusItem menubar).
    let window = AppKitLauncherWindow()
    let menuBar = AppKitMenuBar()
    coordinator.window = window
    coordinator.menuBar = menuBar

    // Host-native providers + the global launcher hotkey, bound via the dispatcher.
    let hotkeys = HotkeyDispatcher(registry: CarbonHotkeyRegistry())
    hotkeys.bind(action: "toggle-launcher",
                 chord: HotkeyChord(keyCode: 49 /* Space */, modifiers: [.command])) {
        MainActor.assumeIsolated { window.showLauncher() }
    }

    // Standard menubar-app run loop (accessory: no Dock icon, menubar only).
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.run()
}
