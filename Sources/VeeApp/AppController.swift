import AppKit
import VeeCore
import VeePluginFormat
import VeeRuntime
import VeePreferences
import VeeTrust
import VeeCatalog
import VeeUI

/// The application delegate. Owns the always-present Vee menu and one coordinator
/// per enabled plugin, watches the plugins directory, and drives the plugin
/// manager.
@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    // Rebuilt once the login-shell PATH is resolved (see applicationDidFinishLaunching).
    private var baseEnvironment = ProcessInfo.processInfo.environment
    private var runtime = PluginRuntime(executor: PluginExecutor(runner: SystemProcessRunner()))
    private var coordinators: [String: PluginCoordinator] = [:]
    private var ephemerals: [String: StatusItemController] = [:]
    private var loadedPaths: Set<String> = []
    private var watcher: PluginDirectoryWatcher?
    private var wakeMonitor: WakeMonitor?
    private var mainMenu: MainMenuController?
    private var generalSettingsModel: GeneralSettingsModel?
    private let prefs = AppPreferences.shared
    private let log = VeeLog.make("app-controller")

    private var directory: String = PluginsDirectory.resolve()

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

        Notifier.requestAuthorization()

        // Resolve the user's real login-shell PATH before loading plugins, so a
        // Finder/Dock launch finds Homebrew/pyenv/asdf/nvm binaries just like a
        // Terminal launch would. The Vee menu is already up; plugins appear once
        // this returns (a short, timed-out shell call).
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
        case .notify(let title, let subtitle, let body, let href):
            Notifier.post(title: title, subtitle: subtitle, body: body, href: href)
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
        let directory = self.directory
        Task { @MainActor in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let source = String(data: data, encoding: .utf8) ?? ""
                guard !source.isEmpty else { return }
                let name = url.lastPathComponent
                let filename = name.isEmpty ? "plugin.1m.sh" : name
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
            coordinators[plugin.id.rawValue] = coordinator
            coordinator.start()
        }
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
            onLaunchAtLogin: { enabled in LoginItemManager.setEnabled(enabled) },
            onOpenFolder: { [weak self] in self?.openFolder() },
            onChooseFolder: { [weak self] in self?.chooseFolder() },
            onRefreshAll: { [weak self] in self?.refreshAll() }
        )
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
        let variables = VariablesEditorModel(groups: groups) { [weak self] in self?.refreshAll() }

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

    private func managerRows() -> [PluginManagerRow] {
        PluginDiscovery.enumerate(directory: directory).map { plugin in
            let source = (try? String(contentsOfFile: plugin.path, encoding: .utf8)) ?? ""
            let header = HeaderParser.parse(source: source)
            let level = TrustAnalyzer.analyze(TrustParser.parse(source: source)).level
            let enabled = plugin.isExecutable && !prefs.isDisabled(plugin.id.rawValue)
            return PluginManagerRow(
                id: plugin.id.rawValue,
                name: plugin.filename.name,
                interval: describe(plugin.filename.interval),
                trust: describe(level),
                isEnabled: enabled,
                hasSettings: !header.vars.isEmpty
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
