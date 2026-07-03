import AppKit
import VeeCore
import VeeRuntime

/// The application delegate. Discovers plugins, drives one coordinator per
/// plugin, watches the plugins directory for changes, and shows a helpful
/// placeholder when there are no plugins yet.
@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    private let runtime = PluginRuntime(executor: PluginExecutor(runner: SystemProcessRunner()))
    private var coordinators: [PluginCoordinator] = []
    private var loadedPaths: Set<String> = []
    private var watcher: PluginDirectoryWatcher?
    private var placeholder: PlaceholderStatusItem?
    private let log = VeeLog.make("app-controller")

    private lazy var directory: String = PluginsDirectory.resolve()

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        PluginsDirectory.ensureExists(directory)
        log.info("plugins directory: \(self.directory, privacy: .public)")
        reload()

        watcher = PluginDirectoryWatcher(directory: directory) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        watcher?.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // Stop coordinators so long-lived (streaming) child processes are
        // terminated rather than orphaned.
        coordinators.forEach { $0.stop() }
        watcher?.stop()
    }

    private func reload() {
        let plugins = PluginDiscovery.enabled(directory: directory)
        let paths = Set(plugins.map(\.path))

        // Only rebuild when the *set* of plugins changes. This avoids a reload
        // storm when a plugin writes files into the watched directory, and
        // preserves each plugin's timer/state across unrelated changes.
        if !coordinators.isEmpty || placeholder != nil, paths == loadedPaths {
            return
        }
        loadedPaths = paths

        coordinators.forEach { $0.stop() }
        coordinators.removeAll()
        placeholder?.remove()
        placeholder = nil

        guard !plugins.isEmpty else {
            placeholder = PlaceholderStatusItem(directory: directory)
            return
        }
        for plugin in plugins {
            let coordinator = PluginCoordinator(plugin: plugin, pluginsDirectory: directory, runtime: runtime)
            coordinators.append(coordinator)
            coordinator.start()
        }
    }
}

/// Shown when the plugins directory is empty: a Vee icon with a menu that opens
/// the folder and quits.
@MainActor
private final class PlaceholderStatusItem: NSObject {
    private let statusItem: NSStatusItem
    private let directory: String

    init(directory: String) {
        self.directory = directory
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "v.circle", accessibilityDescription: "Vee")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let info = NSMenuItem(title: "No plugins yet", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open Plugins Folder…", action: #selector(openFolder), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let quit = NSMenuItem(title: "Quit Vee", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func openFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: directory))
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func remove() { NSStatusBar.system.removeStatusItem(statusItem) }
}
