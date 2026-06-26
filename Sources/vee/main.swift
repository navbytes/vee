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
    let storageFactory: (String) -> StorageBackend = { pluginId in
        // Per-plugin disk store under Application Support/Vee/storage/<pluginId>
        // (R2-HIGH-2: each plugin gets its OWN namespace subfolder, so one plugin's
        // `vee.storage` can't read or overwrite another's keys). A failure to create
        // the directory degrades to in-memory storage rather than crashing the host.
        ((try? DiskStorageBackend(directory: storageRoot, pluginId: pluginId)) as StorageBackend?)
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
        calendarProvider: calendarProvider,
        notificationProvider: UserNotificationProvider())

    // R2-CRIT-2: run plugins OUT OF PROCESS when the child binary is resolvable
    // (the shipped .app bundles `vee-plugin-host` beside `vee`; `swift run` builds
    // it alongside). A crashing plugin then takes down only the child — supervised
    // + restarted below — not the launcher. Falls back to the in-process `host`
    // only when the child binary can't be found / won't launch.
    var childHost: ChildProcessHost?
    if let childURL = ChildProcessHost.defaultChildBinaryURL() {
        let candidate = ChildProcessHost(executableURL: childURL, requestTimeout: 10)
        do { try candidate.start(); childHost = candidate }
        catch {
            FileHandle.standardError.write(Data(
                "vee: out-of-process host unavailable (\(error)); running plugins in-process\n".utf8))
        }
    }

    // ── Installed plugins → generic preferences store (the Raycast model) ─────
    // Discover once, up front: the manifests drive BOTH the per-extension
    // preferences store — which knows nothing about any specific service; it
    // operates purely on what each plugin DECLARED — and the root command list.
    // App enumeration (the heavy startup I/O) still runs on a background hop below.
    let discoveredPlugins = PluginDiscovery.discoverAll()
    let tokenStore = KeychainTokenStore()
    let preferencesStore = PluginPreferencesStore(
        manifests: discoveredPlugins.map(\.manifest),
        secrets: tokenStore)
    // The Settings window edits the hotkey chord + clipboard prefs and renders a
    // GENERIC per-extension preferences form from each plugin's declared specs —
    // no hardcoded GitHub/API-key roster. Built before the coordinator so the
    // "Setup required" gate can open it.
    let settingsController = SettingsWindowController(
        model: settings,
        preferences: preferencesStore,
        onIgnoreNextCopy: { [weak clipboard] in clipboard?.ignoreNextCopy() })

    let coordinatorTransport: CoordinatorTransport
    let activatingHost: PluginActivating
    if let childHost {
        coordinatorTransport = ChildCoordinatorTransport(childHost)
        activatingHost = ChildActivatingHost(childHost)
    } else {
        coordinatorTransport = LoopbackCoordinatorTransport(loopback)
        activatingHost = host
    }
    let coordinator = AppCoordinator(
        pluginId: "com.vee.launcher",
        transport: coordinatorTransport,
        host: activatingHost,
        preferences: preferencesStore,
        onNeedsConfiguration: { pluginId, _ in
            // Raycast "Setup required": a command whose required preferences are
            // unset opens straight to that extension's settings instead of running.
            settingsController.show(focusExtension: pluginId)
        })

    // ── AppKit seams (real NSPanel launcher + NSStatusItem menubar) ───────────
    let window = AppKitLauncherWindow()
    let menuBar = AppKitMenuBar()
    coordinator.window = window
    coordinator.menuBar = menuBar
    menuBar.setMenuBarTitle("Vee")

    // ── Plugin-owned menu-bar commands (Raycast-style menu-bar extras) ────────
    // A `mode: "menu-bar"` command gets its OWN NSStatusItem + dropdown, driven by
    // a MenuBarController that mirrors the command's render tree. The coordinator
    // demuxes those plugins' frames to the controller (off the launcher surface).
    let pluginMenuBar = AppKitPluginMenuBar()
    let menuBarController = MenuBarController(presenter: pluginMenuBar, transport: coordinatorTransport)
    coordinator.menuBarRouter = menuBarController
    var menuBarRefreshTimers: [Timer] = []
    // R2-MED-4: show a loading surface immediately; discovery + app enumeration
    // below replace it via `showHostCandidates`.
    coordinator.showLoading()

    // Supervise the out-of-process host: a plugin crash kills the child (not the
    // launcher), so restart it + re-stage the plugins and return to root. A plugin
    // that *hangs* in activate trips the request watchdog (logged). The shutdown
    // guard stops a deliberate quit from spawning a replacement child.
    var isShuttingDown = false
    childHost?.onTermination = { info in
        FileHandle.standardError.write(Data(
            "vee: plugin host exited (status \(info.status), uncaughtSignal=\(info.byUncaughtSignal))\n".utf8))
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard !isShuttingDown, let ch = childHost else { return }
                try? ch.restart()
                for plugin in discoveredPlugins {
                    _ = try? ch.load(manifest: plugin.manifest, source: plugin.source)
                }
                // Re-activate background menu-bar commands so their status items
                // recover after a child crash (the launcher surface resets below).
                for plugin in discoveredPlugins {
                    for command in plugin.manifest.commands where command.mode == .menuBar {
                        try? activatingHost.activate(ActivateParams(
                            pluginId: plugin.manifest.id, commandName: command.name,
                            preferences: preferencesStore.resolvedValues(
                                pluginId: plugin.manifest.id, command: command.name)))
                    }
                }
                coordinator.showRoot()
            }
        }
    }
    childHost?.onRequestTimeout = { rt in
        FileHandle.standardError.write(Data(
            "vee: plugin host request '\(rt.method)' timed out after \(rt.timeout)s\n".utf8))
    }

    // ── Menubar actions ───────────────────────────────────────────────────────
    // `settingsController` is built above (it backs the generic preferences
    // store). Surface "Settings…" / "Quit Vee" in the menubar.
    menuBar.addActionItem(title: "Settings…", keyEquivalent: ",") {
        settingsController.show()
    }
    menuBar.addSeparator()
    menuBar.addActionItem(title: "Quit Vee", keyEquivalent: "q") {
        isShuttingDown = true
        childHost?.terminate()
        NSApp.terminate(nil)
    }

    // ── Root surface: host-native app search (the pluginless launcher) ────────
    // One filesystem enumeration at startup (fetch once); the coordinator filters
    // this in-memory set natively per keystroke (never re-scans on a keypress).
    let appEnumerator = NSWorkspaceAppEnumerator()
    let appSearch = AppSearchProvider(enumerator: appEnumerator, clock: SystemClock())

    // Stage a discovered plugin into whichever host is active — the out-of-process
    // child when available, else the in-process host (same `host.load` contract).
    let stagePlugin: (PluginManifest, String) -> Bool = { manifest, source in
        if let childHost { return (try? childHost.load(manifest: manifest, source: source)) != nil }
        return (try? host.load(manifest: manifest, source: source)) != nil
    }

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
        let installedApps = appSearch.search(query: "", limit: 5000)

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                var commandCandidates: [Candidate] = []
                for plugin in discoveredPlugins {
                    guard stagePlugin(plugin.manifest, plugin.source) else { continue }
                    for command in plugin.manifest.commands {
                        if command.mode == .menuBar {
                            // Background menu-bar command: it renders into its OWN
                            // status item, not the launcher list. Register it for
                            // demux, activate it now, and refresh on its interval.
                            let id = plugin.manifest.id
                            coordinator.registerMenuBarPlugin(id)
                            menuBarController.register(pluginId: id)
                            let activateMenuBar = {
                                try? activatingHost.activate(ActivateParams(
                                    pluginId: id, commandName: command.name,
                                    preferences: preferencesStore.resolvedValues(
                                        pluginId: id, command: command.name)))
                            }
                            activateMenuBar()
                            if let interval = command.refreshIntervalSeconds, interval > 0 {
                                let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                                    MainActor.assumeIsolated { activateMenuBar() }
                                }
                                menuBarRefreshTimers.append(timer)
                            }
                        } else {
                            // View / no-view command: one launcher root candidate.
                            commandCandidates.append(Candidate(
                                id: "cmd:\(plugin.manifest.id):\(command.name)",
                                title: command.title,
                                subtitle: command.subtitle,
                                icon: plugin.icon,
                                actions: [CandidateAction(id: "run", title: "Open Command")]))
                        }
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
