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
    // ── Snapshot mode (autonomous visual testing) ────────────────────────────
    // `VEE_SNAPSHOT_OUT=/path.png [VEE_SNAPSHOT_DARK=0] [VEE_SNAPSHOT_QUERY=saf]`
    // renders the launcher offscreen and exits — through the REAL pipeline (real
    // app enumeration + coordinator projection), so the snapshot faithfully shows
    // real icons and live filtering. Verifies/iterates the UI headlessly.
    if let snapOut = ProcessInfo.processInfo.environment["VEE_SNAPSHOT_OUT"] {
        _ = NSApplication.shared
        let env = ProcessInfo.processInfo.environment
        let dark = env["VEE_SNAPSHOT_DARK"] != "0"
        let query = env["VEE_SNAPSHOT_QUERY"] ?? ""
        let state = env["VEE_SNAPSHOT_STATE"] ?? "list"

        let window = AppKitLauncherWindow()
        var keepAlive: [AnyObject] = [window]

        switch state {
        case "empty":
            window.setRootViewModel(.empty(EmptyViewModel(
                title: "No Results",
                description: "We couldn't find anything matching your search.")))
        case "detail":
            window.setRootViewModel(.detail(DetailViewModel(
                title: "Vee",
                markdown: "A keyboard-first, plugin-extensible launcher.\n\nPress ⌥Space anywhere to open Vee, type to search your apps and commands, then hit ↩ to run.")))
        case "plugin":
            // Load a REAL @vee/sdk plugin bundle through the JSC engine and render
            // its output in the launcher — proves the full TS→esbuild→JSC→render-
            // tree→AppKit pipeline end to end.
            let loopback = LoopbackTransport()
            let host = PluginHost(transport: loopback, clock: DispatchClock(),
                                  httpClient: URLSessionHTTPClient(), bundler: StaticBundler(source: ""))
            let coordinator = AppCoordinator(
                pluginId: "com.vee.essentials",
                transport: LoopbackCoordinatorTransport(loopback), host: host)
            coordinator.window = window
            let bundlePath = env["VEE_PLUGIN_BUNDLE"]
                ?? (FileManager.default.currentDirectoryPath + "/plugins/fixtures/com.vee.essentials.bundle.js")
            if let source = try? String(contentsOfFile: bundlePath, encoding: .utf8) {
                let manifest = PluginManifest(
                    id: "com.vee.essentials", name: "Essentials", version: "1.0.0",
                    entrypoint: bundlePath,
                    commands: [PluginCommand(name: "view", title: "Essentials", mode: .view)])
                try? host.load(manifest: manifest, source: source)
                try? host.activate(ActivateParams(pluginId: "com.vee.essentials", commandName: "view"))
            }
            keepAlive.append(host)
            keepAlive.append(coordinator)
        default: // "list" — the real app-search pipeline
            let loopback = LoopbackTransport()
            let host = PluginHost(transport: loopback, clock: DispatchClock(),
                                  httpClient: URLSessionHTTPClient(), bundler: StaticBundler(source: ""))
            let coordinator = AppCoordinator(
                pluginId: "com.vee.launcher",
                transport: LoopbackCoordinatorTransport(loopback), host: host)
            coordinator.window = window
            let appSearch = AppSearchProvider(enumerator: NSWorkspaceAppEnumerator(), clock: SystemClock())
            coordinator.showHostCandidates(appSearch.search(query: "", limit: 200),
                                           sectionTitle: "Applications") { _ in }
            if !query.isEmpty { coordinator.setQuery(query) }
            keepAlive.append(host)
            keepAlive.append(coordinator)
        }

        // Let IconServices deliver async app-icon reps before we capture.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.6))
        window.writeSnapshot(to: URL(fileURLWithPath: snapOut),
                             size: NSSize(width: 720, height: 470), dark: dark)
        _ = keepAlive
        exit(0)
    }

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
    // Enumerate installed apps OFF the main thread so the menu bar + hotkey are
    // ready instantly; populate the launcher's candidate set when it's done.
    DispatchQueue.global(qos: .userInitiated).async {
        let installedApps = appSearch.search(query: "", limit: 5000)
        DispatchQueue.main.async {
            coordinator.showHostCandidates(installedApps,
                                           sectionTitle: "Applications") { candidate in
                appSearch.recordLaunch(bundleId: candidate.id)   // feeds frecency next time
                appEnumerator.launch(bundleId: candidate.id)
                window.hideLauncher()
            }
        }
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
