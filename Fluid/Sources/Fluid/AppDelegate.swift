#if os(macOS)
import AppKit
import FluidHostCore

/// Finds plugins, gives each a menu-bar item, and wakes them after sleep.
///
/// Phase 0 loads every `.swift` file in the plugins folder, plus any
/// `--plugin <path>` passed on the command line (a `.swift` file or an
/// already-built helper). With no plugins, a single "Fluid" item offers to
/// install the examples.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var items: [StatusItemController] = []
    private var controllers: [PluginController] = []
    private var emptyStateItem: NSStatusItem?
    private lazy var builder = PluginBuilder(fluidPackage: PluginLibrary.fluidPackage, cacheRoot: PluginLibrary.cacheRoot)
    private let sandbox = ProcessInfo.processInfo.environment["FLUID_SANDBOX"] == "1"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let sources = PluginLibrary.discover()
        sources.forEach(add)
        if sources.isEmpty { showEmptyState() }

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.controllers.forEach { $0.wake() }
            }
        }
    }

    private func add(_ source: URL) {
        let controller = PluginController(source: source)
        controllers.append(controller)
        items.append(StatusItemController(controller: controller))
        let builder = builder
        let sandbox = sandbox
        Task { await controller.load(builder: builder, sandbox: sandbox) }
    }

    private func showEmptyState() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "drop", accessibilityDescription: "Fluid")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "No plugins yet", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let install = NSMenuItem(title: "Install Example Plugins", action: #selector(installExamples), keyEquivalent: "")
        install.target = self
        menu.addItem(install)
        let open = NSMenuItem(title: "Open Plugins Folder", action: #selector(openPluginsFolder), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Fluid", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        emptyStateItem = item
    }

    @objc private func installExamples() {
        let installed = PluginLibrary.installExamples()
        guard !installed.isEmpty else { return }
        if let emptyStateItem { NSStatusBar.system.removeStatusItem(emptyStateItem) }
        emptyStateItem = nil
        installed.forEach(add)
    }

    @objc private func openPluginsFolder() {
        NSWorkspace.shared.open(PluginLibrary.pluginsDirectory)
    }
}

/// Where plugins, FluidKit and the build cache live.
enum PluginLibrary {
    static var pluginsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Fluid/Plugins", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var cacheRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Fluid/builds", isDirectory: true)
    }

    /// The package that provides FluidKit to plugin builds.
    ///
    /// ponytail: development builds find it next to their own source file;
    /// a distributed app will bundle FluidKit (phase 1). FLUID_PACKAGE wins.
    static var fluidPackage: URL {
        if let override = ProcessInfo.processInfo.environment["FLUID_PACKAGE"] {
            return URL(fileURLWithPath: override)
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static func discover() -> [URL] {
        var sources: [URL] = []
        let arguments = CommandLine.arguments
        for (index, argument) in arguments.enumerated() where argument == "--plugin" && index + 1 < arguments.count {
            sources.append(URL(fileURLWithPath: arguments[index + 1]))
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: pluginsDirectory, includingPropertiesForKeys: nil)) ?? []
        sources += files.filter { $0.pathExtension == "swift" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return sources
    }

    /// Copies the example plugins into the plugins folder; returns what it copied.
    static func installExamples() -> [URL] {
        let examples = fluidPackage.appendingPathComponent("Examples", isDirectory: true)
        let files = FileManager.default.enumerator(at: examples, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        return files.compactMap { file in
            let destination = pluginsDirectory.appendingPathComponent(file.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) { return nil }
            return (try? FileManager.default.copyItem(at: file, to: destination)) != nil ? destination : nil
        }
    }
}
#endif
