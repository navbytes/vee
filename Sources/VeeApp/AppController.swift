import AppKit
import VeeCore
import VeePluginFormat
import VeeRuntime
import VeePreferences
import VeeTrust
import VeeUI

/// The application delegate. Owns the always-present Vee menu and one coordinator
/// per enabled plugin, watches the plugins directory, and drives the plugin
/// manager.
@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    private let runtime = PluginRuntime(executor: PluginExecutor(runner: SystemProcessRunner()))
    private var coordinators: [String: PluginCoordinator] = [:]
    private var loadedPaths: Set<String> = []
    private var watcher: PluginDirectoryWatcher?
    private var mainMenu: MainMenuController?
    private let prefs = AppPreferences.shared
    private let log = VeeLog.make("app-controller")

    private lazy var directory: String = PluginsDirectory.resolve()

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        PluginsDirectory.ensureExists(directory)
        log.info("plugins directory: \(self.directory, privacy: .public)")

        mainMenu = MainMenuController(
            onManager: { [weak self] in self?.openManager() },
            onRefreshAll: { [weak self] in self?.refreshAll() },
            onOpenFolder: { [weak self] in self?.openFolder() }
        )

        reload()
        watcher = PluginDirectoryWatcher(directory: directory) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        watcher?.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        coordinators.values.forEach { $0.stop() }
        watcher?.stop()
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
            let coordinator = PluginCoordinator(plugin: plugin, pluginsDirectory: directory, runtime: runtime)
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
            launchAtLogin: LoginItemManager.isEnabled,
            onToggleEnabled: { [weak self] id, enabled in self?.setEnabled(enabled, id: id) },
            onReveal: { [weak self] id in self?.reveal(id) },
            onSettings: { [weak self] id in self?.coordinators[id]?.showSettings() },
            onLaunchAtLogin: { enabled in LoginItemManager.setEnabled(enabled) },
            onOpenFolder: { [weak self] in self?.openFolder() },
            onRefreshAll: { [weak self] in self?.refreshAll() }
        )
        PluginManagerWindow.shared.show(model: model)
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
