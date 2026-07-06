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
    private let prefs = AppPreferences.shared
    private let log = VeeLog.make("app-controller")

    private var directory: String = PluginsDirectory.resolve()

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        PluginsDirectory.ensureExists(directory)
        log.info("plugins directory: \(self.directory, privacy: .public)")

        mainMenu = MainMenuController(
            onManager: { [weak self] in self?.openManager() },
            onDiscover: { [weak self] in self?.openBrowser() },
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

    /// Prompts for a plugins folder (e.g. an existing SwiftBar folder) and
    /// switches to it.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: directory)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setPluginsDirectory(url.path)
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
