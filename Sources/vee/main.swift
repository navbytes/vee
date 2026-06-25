import AppKit
import VeeApp
import VeeEngine
import VeeServices
import VeeProtocol

// Thin executable entrypoint — NSApplication bootstrap + wiring ONLY. Every
// decision lives in the tested libraries (VeeApp/VeeEngine/VeeServices/VeeFuzzy);
// here we just construct the real seam adapters and connect them. `main.swift`
// runs on the main thread, so AppKit (`@MainActor`) construction happens inside
// `MainActor.assumeIsolated` — the run loop owns the main actor from here on.
MainActor.assumeIsolated {
    // ── Plugin host + transport ──────────────────────────────────────────────
    // In-memory loopback for now (the JSON-RPC contract is shaped so a real
    // out-of-process fd/DispatchIO transport swaps in here later untouched). The
    // host is wired with the REAL hot-reload infra (FSEvents watcher + esbuild
    // bundler); these stay dormant until a JS plugin is loaded via `host.load`.
    let pluginsDir: URL = {
        if let p = ProcessInfo.processInfo.environment["VEE_PLUGINS_DIR"] {
            return URL(fileURLWithPath: p)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("plugins")
    }()

    let loopback = LoopbackTransport()
    let host = PluginHost(
        transport: loopback,
        clock: DispatchClock(),
        httpClient: URLSessionHTTPClient(),
        fileWatcher: FSEventsFileWatcher(pathForPlugin: { id in
            pluginsDir.appendingPathComponent("dist/\(id).js").path
        }),
        bundler: EsbuildBundler(workingDirectory: pluginsDir))

    let coordinator = AppCoordinator(
        pluginId: "com.vee.launcher",
        transport: LoopbackCoordinatorTransport(loopback),
        host: host)

    // ── AppKit seams (real NSPanel launcher + NSStatusItem menubar) ───────────
    let window = AppKitLauncherWindow()
    let menuBar = AppKitMenuBar()
    coordinator.window = window
    coordinator.menuBar = menuBar
    menuBar.setMenuBarTitle("Vee")

    // ── Root surface: host-native app search (the pluginless launcher) ────────
    // One filesystem enumeration at startup (fetch once); the coordinator filters
    // this in-memory set natively per keystroke (never re-scans on a keypress).
    let appEnumerator = NSWorkspaceAppEnumerator()
    let appSearch = AppSearchProvider(enumerator: appEnumerator, clock: SystemClock())
    let installedApps = appSearch.search(query: "", limit: 5000)
    coordinator.showHostCandidates(installedApps) { candidate in
        appSearch.recordLaunch(bundleId: candidate.id)   // feeds frecency next time
        appEnumerator.launch(bundleId: candidate.id)
        window.hideLauncher()
    }

    // ── Clipboard history service (real NSPasteboard, privacy-filtered) ───────
    // Captures into an in-memory, concealed/transient-respecting history on a
    // background poll. (A clipboard command/UI surface is a follow-up.)
    let clipboard = ClipboardMonitor(pasteboard: NSPasteboardReader(), clock: SystemClock())
    let clipboardPoll = ClipboardPollDriver(monitor: clipboard)
    clipboardPoll.start()

    // ── Global launcher hotkey (Option+Space, Alfred-style) ───────────────────
    // Cmd+Space is intentionally avoided (Spotlight owns it system-wide and the
    // OS would refuse the registration). Option+Space is a conventional launcher
    // chord; rebind here as desired. (A recorder UI is a follow-up.)
    let hotkeys = HotkeyDispatcher(registry: CarbonHotkeyRegistry())
    let bindResult = hotkeys.bind(
        action: "toggle-launcher",
        chord: HotkeyChord(keyCode: 49 /* Space */, modifiers: [.option])) {
            MainActor.assumeIsolated { window.showLauncher() }
        }
    if bindResult != .registered {
        FileHandle.standardError.write(Data("vee: launcher hotkey not registered: \(bindResult)\n".utf8))
    }

    // Keep strong references alive for the process lifetime (the run loop owns
    // the app; these would otherwise deallocate at the end of this scope).
    _ = (host, coordinator, clipboard, clipboardPoll, hotkeys)

    // ── Run loop: menubar accessory (no Dock icon) ────────────────────────────
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.run()
}
