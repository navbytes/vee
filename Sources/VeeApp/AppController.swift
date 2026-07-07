import AppKit
import VeeCore
import VeePluginFormat
import VeeRuntime
import VeePreferences
import VeeTrust
import VeeCatalog
import VeeUI
import VeeWidgetShared
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The application delegate. Owns the always-present Vee menu and one coordinator
/// per enabled plugin, watches the plugins directory, and drives the plugin
/// manager.
@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    // Rebuilt once the login-shell PATH is resolved (see applicationDidFinishLaunching).
    private var baseEnvironment = ProcessInfo.processInfo.environment
    private var runtime = PluginRuntime(executor: PluginExecutor(runner: SystemProcessRunner()))
    private var coordinators: [String: PluginCoordinator] = [:]
    /// The Plugin Manager model while its window is open, held weakly so live
    /// per-plugin error updates can be pushed into it. Nil when the window is closed.
    private weak var currentManagerModel: PluginManagerModel?
    private var ephemerals: [String: StatusItemController] = [:]
    private var loadedPaths: Set<String> = []
    private var watcher: PluginDirectoryWatcher?
    private var wakeMonitor: WakeMonitor?
    private var mainMenu: MainMenuController?
    private var generalSettingsModel: GeneralSettingsModel?
    private let prefs = AppPreferences.shared
    private let log = VeeLog.make("app-controller")

    private var directory: String = PluginsDirectory.resolve()

    /// Latest published title per plugin, mirrored to the shared snapshot file
    /// so the WidgetKit widget can render it. Flushed (coalesced) on change.
    private var snapshotItems: [String: PluginSnapshot] = [:]
    private var snapshotFlushScheduled = false
    /// The content last written (with volatile timestamps normalized away), so an
    /// unchanged flush is a no-op: a plugin re-running with identical output —
    /// same title, color, gauge, error state — must not churn the file or spend a
    /// widget reload.
    private var lastPublishedSignature: [PluginSnapshot] = []
    /// Throttle state for `WidgetCenter.reloadAllTimelines()` — WidgetKit meters
    /// reloads against a per-app budget, so a fast/streaming plugin must not
    /// drive one reload per tick.
    private var lastWidgetReload: Date = .distantPast
    private var widgetReloadPending = false

    /// The running controller, so App Intents (Shortcuts/Spotlight) can drive it.
    public static weak var shared: AppController?

    public override init() {
        super.init()
        Self.shared = self
    }

    // MARK: - Intent entry points (Shortcuts / Spotlight)

    /// Re-runs every enabled plugin. Exposed for App Intents.
    public func intentRefreshAll() { refreshAll() }

    /// Re-runs one plugin by name (its filename id). Returns whether it matched.
    @discardableResult
    public func intentRefresh(name: String) -> Bool {
        guard let coordinator = coordinators[name] else { return false }
        coordinator.forceRefresh()
        return true
    }

    /// Enables or disables one plugin by name. Exposed for App Intents.
    public func intentSetEnabled(_ enabled: Bool, name: String) { setEnabled(enabled, id: name) }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        PluginsDirectory.ensureExists(directory)
        log.info("plugins directory: \(self.directory, privacy: .public)")

        installAppMenu()

        mainMenu = MainMenuController(
            onManager: { [weak self] in self?.openManager() },
            onDiscover: { [weak self] in self?.openBrowser() },
            onPreferences: { [weak self] in self?.openPreferences() },
            onRefreshAll: { [weak self] in self?.refreshAll() },
            onOpenFolder: { [weak self] in self?.openFolder() }
        )

        // Register the notification delegate + action categories now, but defer
        // the permission prompt until a plugin actually posts an alert, so the
        // system dialog appears in context rather than at a cold launch.
        Notifier.prepare()
        // Wire the plugin-alert action buttons to the live coordinators:
        // Re-run refreshes the plugin; Open-log opens its debug console.
        Notifier.configure(
            onRerun: { [weak self] id in self?.coordinators[id]?.forceRefresh() },
            onOpenLog: { [weak self] id in self?.coordinators[id]?.showDebugConsole() }
        )

        presentFirstRunIfNeeded()

        // Resolve the user's real login-shell PATH before loading plugins, so a
        // Finder/Dock launch finds Homebrew/pyenv/asdf/nvm binaries just like a
        // Terminal launch would. The Vee menu is already up; plugins appear once
        // this returns (a short, timed-out shell call).
        // Refresh immediately when the Control Center control fires while Vee is
        // already running. (A cold start needs no flag: the control launches Vee
        // via openAppWhenRun, and Vee refreshes every plugin on launch.)
        registerControlRefreshObserver()

        Task { @MainActor in
            self.baseEnvironment = await ShellPathResolver.resolvedEnvironment()
            self.runtime = PluginRuntime(executor: PluginExecutor(runner: SystemProcessRunner(), baseEnvironment: self.baseEnvironment))
            self.reload()
            self.startWatching()
        }

        let monitor = WakeMonitor { [weak self] in self?.refreshAll() }
        monitor.start()
        wakeMonitor = monitor
    }

    private func startWatching() {
        watcher?.stop()
        watcher = PluginDirectoryWatcher(directory: directory) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        watcher?.start()
    }

    // MARK: - URL scheme (vee:// and swiftbar://)

    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { perform(URLActionRouter.parse(url)) }
    }

    private func perform(_ action: URLAction) {
        switch action {
        case .refreshAll:
            refreshAll()
        case .refreshPlugin(let name):
            coordinators[name]?.forceRefresh()
        case .enablePlugin(let name):
            setEnabled(true, id: name)
        case .disablePlugin(let name):
            setEnabled(false, id: name)
        case .togglePlugin(let name):
            setEnabled(prefs.isDisabled(name), id: name)
        case .addPlugin(let src):
            installPlugin(from: src)
        case .setEphemeralPlugin(let name, let content, let exitAfter):
            showEphemeral(name: name, content: content, exitAfter: exitAfter)
        case .notify(let title, let subtitle, let body, let href, let pluginID):
            Notifier.post(title: title, subtitle: subtitle, body: body, href: href, pluginID: pluginID)
        case .unknown:
            break
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        coordinators.values.forEach { $0.stop() }
        ephemerals.values.forEach { $0.remove() }
        wakeMonitor?.stop()
        watcher?.stop()
    }

    /// `swiftbar://addplugin?src=…`: download a plugin and install it.
    private func installPlugin(from url: URL) {
        // Only fetch over real web schemes — never `file://` (which would read a
        // local file and install it as an executable) or other schemes.
        guard URLScheme.isWebURL(url) else {
            log.error("addplugin rejected non-web src scheme: \(url.scheme ?? "nil", privacy: .public)")
            return
        }
        let directory = self.directory
        Task { @MainActor in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let source = String(data: data, encoding: .utf8) ?? ""
                guard !source.isEmpty else { return }
                // `lastPathComponent` percent-decodes, so a crafted `src` can
                // carry path separators here; PluginInstaller sanitizes, but fall
                // back to a fixed name when the component is unusable.
                let name = url.lastPathComponent
                let filename = (try? PluginInstaller.sanitizedFilename(name)) ?? "plugin.1m.sh"
                try PluginInstaller.install(filename: filename, source: source, into: directory)
                self.reload()
            } catch {
                self.log.error("addplugin failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// `swiftbar://setephemeralplugin?name=…&content=…&exitafter=N`: show
    /// transient menu content in its own status item, without a file on disk.
    private func showEphemeral(name: String, content: String, exitAfter: TimeInterval?) {
        let key = name.isEmpty ? UUID().uuidString : name
        let controller: StatusItemController
        if let existing = ephemerals[key] {
            controller = existing
        } else {
            controller = StatusItemController(
                pluginName: key,
                handler: AppActionDispatcher(runner: SystemProcessRunner(), baseEnvironment: baseEnvironment) {},
                onRefresh: {}
            )
            ephemerals[key] = controller
        }
        controller.render(OutputParser.parse(content))
        if let exitAfter, exitAfter > 0 {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(exitAfter * 1_000_000_000))
                self.ephemerals[key]?.remove()
                self.ephemerals[key] = nil
            }
        }
    }

    // MARK: - Loading

    private func enabledPlugins() -> [DiscoveredPlugin] {
        PluginDiscovery.enabled(directory: directory).filter { !prefs.isDisabled($0.id.rawValue) }
    }

    private func reload() {
        let plugins = enabledPlugins()
        let paths = Set(plugins.map(\.path))
        // Only rebuild when the effective set changes (avoids reload storms from
        // in-directory writes; preserves timers/state otherwise).
        if !coordinators.isEmpty, paths == loadedPaths { return }
        loadedPaths = paths

        coordinators.values.forEach { $0.stop() }
        coordinators.removeAll()

        for plugin in plugins {
            let coordinator = PluginCoordinator(plugin: plugin, pluginsDirectory: directory, runtime: runtime, baseEnvironment: baseEnvironment)
            let id = plugin.id.rawValue
            let name = plugin.filename.name
            let interval = plugin.filename.interval.timeInterval
            coordinator.onPublish = { [weak self] publish in
                self?.publishToWidget(id: id, name: name, interval: interval, publish: publish)
                // Keep an open Plugin Manager's error badge live: push this run's
                // error state (nil on success) into the row. Cheap — setError
                // only mutates when the value actually changed.
                self?.currentManagerModel?.setError(self?.coordinators[id]?.lastError, id: id)
            }
            coordinators[id] = coordinator
            coordinator.start()
        }
        // Drop widget entries for plugins that are no longer loaded.
        flushWidgetSnapshot()
    }

    // MARK: - Widget snapshot

    /// Minimum spacing between `reloadAllTimelines()` calls. WidgetKit meters
    /// background reloads against a per-app daily budget; a fast (e.g. `5s`) or
    /// streaming plugin would otherwise blow through it in minutes and leave the
    /// widget frozen. The widget's own 30-min timeline policy is the in-budget
    /// baseline; these pushes just make changes appear sooner.
    private static let widgetReloadMinInterval: TimeInterval = 300 // 5 minutes

    /// Records a plugin's current widget state and schedules a coalesced flush to
    /// the shared snapshot file so the WidgetKit widget can render it.
    private func publishToWidget(id: String, name: String, interval: TimeInterval?, publish: WidgetPublish) {
        snapshotItems[id] = PluginSnapshot(
            id: id,
            name: name,
            title: publish.title,
            updated: Date(),
            color: publish.fields.color.map(WidgetSnapshotMapping.snapshotColor),
            symbolName: publish.fields.symbolName,
            symbolColors: WidgetSnapshotMapping.snapshotColors(publish.fields.symbolColors),
            progress: publish.fields.progress,
            sparkline: publish.fields.sparkline,
            isError: publish.isError,
            interval: interval
        )
        guard !snapshotFlushScheduled else { return }
        snapshotFlushScheduled = true
        Task { @MainActor in
            // Coalesce bursts (many plugins refreshing at once) into one write.
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.snapshotFlushScheduled = false
            self.flushWidgetSnapshot()
        }
    }

    /// Writes the current snapshot (only currently-loaded plugins, name-sorted)
    /// to the shared file — always, so freshness timestamps stay honest — and asks
    /// WidgetKit to reload only when the visible *content* changed (and never more
    /// often than the reload floor).
    private func flushWidgetSnapshot() {
        snapshotItems = snapshotItems.filter { coordinators[$0.key] != nil }
        let plugins = snapshotItems.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
        // Detect a visible-content change (title, color, gauge, error state) with
        // the per-run `updated` timestamp normalized away, so a plugin re-running
        // with identical output doesn't spend a widget reload.
        let signature = Self.contentSignature(plugins)
        let contentChanged = signature != lastPublishedSignature
        lastPublishedSignature = signature

        // Always write, so the on-disk per-plugin `updated` (and `generated`)
        // stay current: freshness must reflect "last ran", not "last content
        // change", or a healthy plugin with steady output would wrongly render as
        // stale after a few minutes. Only a *visible content* change is worth a
        // metered WidgetKit reload — an unchanged re-run just refreshes timestamps.
        VeeWidgetSharing.shared.write(WidgetSnapshot(plugins: Array(plugins), generated: Date()))
        if contentChanged { requestWidgetReload() }
    }

    /// The change-detection key for a set of snapshots: the same plugins with the
    /// per-run `updated` timestamp zeroed, so re-running a plugin with identical
    /// output compares equal (only a real content change triggers a widget reload;
    /// the file itself is still rewritten to keep `updated` current).
    private static func contentSignature(_ plugins: [PluginSnapshot]) -> [PluginSnapshot] {
        plugins.map {
            PluginSnapshot(
                id: $0.id, name: $0.name, title: $0.title,
                updated: Date(timeIntervalSince1970: 0),
                color: $0.color, symbolName: $0.symbolName, symbolColors: $0.symbolColors,
                progress: $0.progress, sparkline: $0.sparkline, isError: $0.isError, interval: $0.interval
            )
        }
    }

    /// Asks WidgetKit to reload, throttled to `widgetReloadMinInterval`. If a
    /// reload happened recently, one trailing reload is scheduled at the end of
    /// the window so the latest change still lands.
    private func requestWidgetReload() {
        #if canImport(WidgetKit)
        let now = Date()
        let elapsed = now.timeIntervalSince(lastWidgetReload)
        if elapsed >= Self.widgetReloadMinInterval {
            lastWidgetReload = now
            WidgetCenter.shared.reloadAllTimelines()
        } else if !widgetReloadPending {
            widgetReloadPending = true
            let delay = Self.widgetReloadMinInterval - elapsed
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                self.widgetReloadPending = false
                self.lastWidgetReload = Date()
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        #endif
    }

    // MARK: - Control Center refresh

    /// Observes the Darwin notification the control posts, so a refresh fires
    /// immediately when Vee is already running.
    private func registerControlRefreshObserver() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, _, _, _, _ in
                Task { @MainActor in AppController.shared?.controlRefreshFired() }
            },
            VeeWidgetSharing.refreshRequestNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    func controlRefreshFired() {
        refreshAll()
    }

    // MARK: - Global actions

    private func refreshAll() { coordinators.values.forEach { $0.forceRefresh() } }

    private func openFolder() { NSWorkspace.shared.open(URL(fileURLWithPath: directory)) }

    private func openManager() {
        let model = PluginManagerModel(
            rows: managerRows(),
            currentDirectory: directory,
            launchAtLogin: LoginItemManager.isEnabled,
            onToggleEnabled: { [weak self] id, enabled in self?.setEnabled(enabled, id: id) },
            onReveal: { [weak self] id in self?.reveal(id) },
            onSettings: { [weak self] id in self?.coordinators[id]?.showSettings() },
            onDebug: { [weak self] id in self?.coordinators[id]?.showDebugConsole() },
            onDelete: { [weak self] id in self?.deletePlugin(id) },
            onDiscover: { [weak self] in self?.openBrowser() },
            onLaunchAtLogin: { enabled in LoginItemManager.setEnabled(enabled) },
            onOpenFolder: { [weak self] in self?.openFolder() },
            onChooseFolder: { [weak self] in self?.chooseFolder() },
            onRefreshAll: { [weak self] in self?.refreshAll() }
        )
        // Held weakly so coordinators can push live error updates into the open
        // window; the window retains the model, so this nils out once it closes.
        currentManagerModel = model
        PluginManagerWindow.shared.show(model: model)
    }

    private func openBrowser() {
        let model = PluginBrowserModel(
            fetcher: GitHubCatalogClient(),
            pluginsDirectory: directory,
            onInstalled: { [weak self] in self?.reload() }
        )
        PluginBrowserWindow.shared.show(model: model)
    }

    /// On the very first launch, a brand-new user sees only a menu-bar icon and
    /// has to guess what to do. If their plugins folder is also empty, open
    /// Discover once so there's an obvious next step. Existing SwiftBar/xbar
    /// users (who already have plugins) are left undisturbed.
    private func presentFirstRunIfNeeded() {
        guard !prefs.hasCompletedFirstRun else { return }
        prefs.hasCompletedFirstRun = true
        if PluginDiscovery.enumerate(directory: directory).isEmpty {
            openBrowser()
        }
    }

    // MARK: - Preferences

    /// Installs a minimal application main menu. Vee is an `.accessory` app so
    /// this menu is never shown, but its key equivalents (⌘, for Preferences,
    /// and the standard Edit-menu clipboard commands used when pasting API
    /// tokens into the Variables editor) are dispatched to the key window.
    private func installAppMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        let prefs = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.keyEquivalentModifierMask = [.command]
        prefs.target = self
        appMenu.addItem(prefs)

        let editItem = NSMenuItem()
        editItem.title = "Edit"
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    /// Opens the app-wide Preferences window (⌘,): a General tab reusing the
    /// app-level settings and a Variables tab aggregating every installed
    /// plugin's declared `<xbar.var>` variables.
    @objc private func openPreferences() {
        let general = GeneralSettingsModel(
            currentDirectory: directory,
            launchAtLogin: LoginItemManager.isEnabled,
            onLaunchAtLogin: { LoginItemManager.setEnabled($0) },
            onChooseFolder: { [weak self] in self?.chooseFolderFromPreferences() },
            onOpenFolder: { [weak self] in self?.openFolder() },
            onRefreshAll: { [weak self] in self?.refreshAll() }
        )
        self.generalSettingsModel = general

        let groups = VariableAggregator.aggregate(plugins: aggregatablePlugins(), reader: HeaderVariableReader())
        let variables = VariablesEditorModel(groups: groups, onSaved: { [weak self] in self?.refreshAll() })

        PreferencesWindow.shared.show(general: general, variables: variables)
    }

    /// Every installed plugin, described for the pure variable aggregator.
    private func aggregatablePlugins() -> [AggregatablePlugin] {
        PluginDiscovery.enumerate(directory: directory).map {
            AggregatablePlugin(id: $0.id, name: $0.filename.name, path: $0.path)
        }
    }

    /// Folder chooser invoked from the Preferences General tab; also refreshes
    /// the tab's displayed path so it stays in sync.
    private func chooseFolderFromPreferences() {
        guard let path = promptForPluginsFolder() else { return }
        setPluginsDirectory(path)
        generalSettingsModel?.currentDirectory = path
    }

    /// Prompts for a plugins folder (e.g. an existing SwiftBar folder) and
    /// switches to it.
    private func chooseFolder() {
        guard let path = promptForPluginsFolder() else { return }
        setPluginsDirectory(path)
    }

    /// Runs the open panel and returns the chosen folder path, or `nil` if
    /// cancelled.
    private func promptForPluginsFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: directory)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    private func setPluginsDirectory(_ path: String) {
        prefs.pluginsDirectory = path
        directory = path
        PluginsDirectory.ensureExists(directory)
        loadedPaths.removeAll()
        reload()
        startWatching()
    }

    private func setEnabled(_ enabled: Bool, id: String) {
        prefs.setDisabled(!enabled, id: id)
        reload()
    }

    private func reveal(_ id: String) {
        guard let plugin = PluginDiscovery.enumerate(directory: directory).first(where: { $0.id.rawValue == id }) else { return }
        NSWorkspace.shared.selectFile(plugin.path, inFileViewerRootedAtPath: directory)
    }

    /// Moves a plugin's script to the Trash (recoverable) and reloads so its
    /// status item and coordinator are torn down. The manager has already removed
    /// the row optimistically. `loadedPaths` is deliberately left untouched: it's
    /// the change-detection baseline reload() compares against, so leaving the
    /// now-deleted path in it guarantees reload() sees the diff and rebuilds
    /// (removing it here would make reload() short-circuit and orphan the item).
    private func deletePlugin(_ id: String) {
        guard let plugin = PluginDiscovery.enumerate(directory: directory).first(where: { $0.id.rawValue == id }) else { return }
        try? FileManager.default.trashItem(at: URL(fileURLWithPath: plugin.path), resultingItemURL: nil)
        reload()
    }

    private func managerRows() -> [PluginManagerRow] {
        PluginDiscovery.enumerate(directory: directory).map { plugin in
            let source = (try? String(contentsOfFile: plugin.path, encoding: .utf8)) ?? ""
            let header = HeaderParser.parse(source: source)
            let level = TrustAnalyzer.analyze(TrustParser.parse(source: source)).level
            let id = plugin.id.rawValue
            let enabled = plugin.isExecutable && !prefs.isDisabled(id)
            // Declared features gate Settings reachability (so a disabled hotkey
            // stays re-enable-able); the indicators reflect the *effective* state.
            let declaredFeatures = PluginFeatures(header: header)
            let effectiveHotkey: String?
            if case .use(let spec) = EffectiveHotkey.resolve(
                declared: header.shortcut,
                userDisabled: prefs.isHotkeyDisabled(id),
                customBinding: prefs.hotkeyBinding(id)
            ) {
                effectiveHotkey = spec.display
            } else {
                effectiveHotkey = nil
            }
            return PluginManagerRow(
                id: id,
                name: plugin.filename.name,
                interval: describe(plugin.filename.interval),
                trust: describe(level),
                isEnabled: enabled,
                hasSettings: !header.vars.isEmpty || !declaredFeatures.isEmpty,
                features: PluginFeatures(searchPanel: header.filter, hotkey: effectiveHotkey),
                lastError: coordinators[id]?.lastError
            )
        }
    }

    private func describe(_ interval: RefreshInterval) -> String {
        switch interval {
        case .manual: return "on demand"
        case .milliseconds(let n): return "\(n)ms"
        case .seconds(let n): return "every \(n)s"
        case .minutes(let n): return "every \(n)m"
        case .hours(let n): return "every \(n)h"
        case .days(let n): return "every \(n)d"
        case .cron(let e): return "cron: \(e)"
        }
    }

    private func describe(_ level: TrustLevel) -> String {
        switch level {
        case .declared: return "capabilities declared"
        case .partial: return "capabilities incomplete"
        case .undeclared: return ""
        }
    }
}
