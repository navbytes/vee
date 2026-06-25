import AppKit
import VeeApp
import VeeEngine
import VeeServices
import VeeProtocol
import VeeKeychain

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
            let cmds = [
                Candidate(id: "cmd:com.vee.essentials:view", title: "Essentials", icon: "command",
                          actions: [CandidateAction(id: "run", title: "Open Command")]),
                Candidate(id: "cmd:com.vee.clipboard:view", title: "Clipboard History", icon: "doc.on.clipboard",
                          actions: [CandidateAction(id: "run", title: "Open Command")]),
                Candidate(id: "cmd:com.vee.hacker-news:view", title: "Hacker News", icon: "newspaper",
                          actions: [CandidateAction(id: "run", title: "Open Command")]),
            ]
            coordinator.showHostCandidates(cmds + appSearch.search(query: "", limit: 200)) { _ in }
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

    // ── Persisted settings (hotkey chord, clipboard history size + blocklist) ─
    // Loaded up front so the clipboard monitor is sized correctly at birth and
    // the hotkey binds to the user's saved chord.
    let settings = SettingsModel()

    // ── Clipboard history service (real NSPasteboard, privacy-filtered) ───────
    // Captures into an in-memory, concealed/transient-respecting history on a
    // background poll. Constructed BEFORE the host so its provider adapter can be
    // injected. The history cap comes from saved settings (the cap is fixed at
    // init); the user-added blocklist UTIs are layered on top of the always-on
    // privacy conventions.
    let clipboard = ClipboardMonitor(pasteboard: NSPasteboardReader(),
                                     clock: SystemClock(),
                                     historyLimit: settings.historySize)
    for type in settings.blocklist { clipboard.addToBlocklist(type) }
    let clipboardPoll = ClipboardPollDriver(monitor: clipboard)
    clipboardPoll.start()

    // ── Real bridge providers (app-side adapters over live services) ──────────
    // The engine ships safe defaults; here we wire the REAL backends so a loaded
    // plugin's `vee.*` calls actually function: clipboard history/copy, calendar
    // (lazy EventKit), open/openApp (NSWorkspace), fs (FileManager), per-plugin
    // disk storage under Application Support, and keychain-backed secrets (used
    // by e.g. the GitHub plugin once a token is saved in Settings).
    let storageRoot = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Vee", isDirectory: true)
        .appendingPathComponent("storage", isDirectory: true)
        ?? URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Vee/storage", isDirectory: true)

    // Bind each provider to an explicitly-typed local first; this gives the type
    // checker firm anchors for the multi-argument `PluginHost(...)` call (an
    // inline tower of differently-typed args otherwise defeats inference here).
    let clipboardProvider: ClipboardProviding = ClipboardMonitorProvider(monitor: clipboard)
    let calendarProvider: CalendarProviding = EventKitCalendarAdapter()
    let openProvider: OpenProviding = NSWorkspaceOpenProvider()
    let fileProvider: FileProviding = FileManagerFileProvider()
    let secretStore: any SecretStore = VeeKeychain.KeychainStore()
    let storageFactory: () -> StorageBackend = {
        // One disk-backed store rooted under Application Support/Vee/storage. The
        // factory signature carries no plugin id, so all plugins share this
        // namespace subfolder (acceptable for self-authored plugins; this is
        // capability gating, not a hostile sandbox). A failure to create the
        // directory degrades to in-memory storage rather than crashing the host.
        // (`as StorageBackend?` so `??` unifies the two concrete impls cleanly.)
        ((try? DiskStorageBackend(directory: storageRoot, pluginId: "plugins")) as StorageBackend?)
            ?? InMemoryStorage()
    }

    let loopback = LoopbackTransport()
    let host = PluginHost(
        transport: loopback,
        clock: DispatchClock(),
        httpClient: URLSessionHTTPClient(),
        fileWatcher: FSEventsFileWatcher(pathForPlugin: { id in
            pluginsDir.appendingPathComponent("dist/\(id).js").path
        }),
        bundler: EsbuildBundler(workingDirectory: pluginsDir),
        storageFactory: storageFactory,
        clipboardProvider: clipboardProvider,
        secretStore: secretStore,
        openProvider: openProvider,
        fileProvider: fileProvider,
        calendarProvider: calendarProvider)

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

    // ── Settings window + menubar actions ─────────────────────────────────────
    // Tokens are stored in the real Keychain (namespace "tokens"); the Settings
    // window edits the hotkey chord, clipboard history size + blocklist, and the
    // per-plugin tokens. Construct it lazily-once and surface "Settings…" / "Quit
    // Vee" in the menubar.
    let tokenStore = KeychainTokenStore()
    let settingsController = SettingsWindowController(
        model: settings,
        tokenStore: tokenStore,
        onIgnoreNextCopy: { [weak clipboard] in clipboard?.ignoreNextCopy() })
    menuBar.addActionItem(title: "Settings…", keyEquivalent: ",") {
        settingsController.show()
    }
    menuBar.addSeparator()
    menuBar.addActionItem(title: "Quit Vee", keyEquivalent: "q") {
        NSApp.terminate(nil)
    }

    // ── Root surface: host-native app search (the pluginless launcher) ────────
    // One filesystem enumeration at startup (fetch once); the coordinator filters
    // this in-memory set natively per keystroke (never re-scans on a keypress).
    let appEnumerator = NSWorkspaceAppEnumerator()
    let appSearch = AppSearchProvider(enumerator: appEnumerator, clock: SystemClock())

    // ── Discover + load plugins from disk; surface each command in the root ───
    // Production: Resources/vee-plugins/<id>/{vee.json,bundle.js}. Dev fallback:
    // plugins/samples/*/vee.json + plugins/fixtures/<id>.bundle.js. Each loaded
    // plugin contributes a "cmd:<id>:<command>" root candidate per command;
    // invoking it activates the plugin, which then renders into the launcher.
    //
    // Discovery (filesystem reads) + bundle evaluation happen OFF the main thread
    // so the menu bar + hotkey are ready instantly; we hop back to the main thread
    // to mutate the host (instances dictionary) and publish candidates. App
    // enumeration runs on the same background hop.
    DispatchQueue.global(qos: .userInitiated).async {
        let discovered = PluginDiscovery.discoverAll()
        let installedApps = appSearch.search(query: "", limit: 5000)

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                var commandCandidates: [Candidate] = []
                for plugin in discovered {
                    guard (try? host.load(manifest: plugin.manifest, source: plugin.source)) != nil
                    else { continue }
                    // One root candidate per declared command (most plugins ship a
                    // single "view" command, but honor multiples).
                    for command in plugin.manifest.commands {
                        commandCandidates.append(Candidate(
                            id: "cmd:\(plugin.manifest.id):\(command.name)",
                            title: command.title,
                            subtitle: command.subtitle,
                            icon: plugin.icon,
                            actions: [CandidateAction(id: "run", title: "Open Command")]))
                    }
                }

                // Commands first, then apps. Invoking a "cmd:" candidate activates
                // the plugin (which renders into the launcher); an app candidate
                // launches it.
                coordinator.showHostCandidates(commandCandidates + installedApps) { candidate in
                    if candidate.id.hasPrefix("cmd:") {
                        let parts = candidate.id.split(separator: ":", maxSplits: 2).map(String.init)
                        if parts.count == 3 {
                            // Retarget the coordinator to this plugin's id (ARCH-1)
                            // AND activate it, so the plugin's render reaches the
                            // window instead of being filtered out.
                            coordinator.activatePlugin(parts[1], command: parts[2])
                        }
                        // The plugin now drives the surface; keep the launcher open.
                    } else {
                        appSearch.recordLaunch(bundleId: candidate.id)   // feeds frecency next time
                        appEnumerator.launch(bundleId: candidate.id)
                        window.hideLauncher()
                    }
                }
            }
        }
    }

    // ── Global launcher hotkey (saved chord, fallback ⌥Space) ─────────────────
    // Cmd+Space is intentionally avoided (Spotlight owns it system-wide and the
    // OS would refuse the registration). The bound chord comes from saved settings
    // (default ⌥Space); the recorder in Settings re-binds it live via the model's
    // change callback below.
    let hotkeys = HotkeyDispatcher(registry: CarbonHotkeyRegistry())
    let toggleLauncher: () -> Void = {
        MainActor.assumeIsolated {
            coordinator.showRoot()   // back to the app/command root on every open
            window.showLauncher()
        }
    }
    func bindLauncherHotkey(_ chord: HotkeyChord) {
        let result = hotkeys.bind(action: "toggle-launcher", chord: chord, handler: toggleLauncher)
        if result != .registered {
            FileHandle.standardError.write(
                Data("vee: launcher hotkey not registered (\(chord)): \(result)\n".utf8))
        }
    }
    bindLauncherHotkey(settings.hotkey)

    // ── Live settings → running services ──────────────────────────────────────
    // Re-bind the global hotkey when the recorder reports a new chord; apply
    // blocklist edits to the live clipboard monitor immediately. (Owned by a small
    // helper so the bootstrap closure stays lean.)
    let settingsBinder = SettingsBinder(
        model: settings,
        clipboard: clipboard,
        rebindHotkey: { chord in bindLauncherHotkey(chord) })
    settingsBinder.activate()

    // Keep strong references alive for the process lifetime (the run loop owns
    // the app; these would otherwise deallocate at the end of this scope).
    _ = (host, coordinator, clipboard, clipboardPoll, hotkeys, settings,
         settingsController, settingsBinder, calendarProvider)

    // ── Run loop: menubar accessory (no Dock icon) ────────────────────────────
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.run()
}
