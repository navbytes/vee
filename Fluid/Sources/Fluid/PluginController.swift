#if os(macOS)
import Foundation
import Observation
import FluidHostCore
import FluidProtocol

/// One plugin as the UI sees it: its build, its supervisor, and the latest
/// trees for each surface, observable by SwiftUI and the status item.
@MainActor
@Observable
final class PluginController: Identifiable {
    let id: String
    let source: URL
    private(set) var name: String
    private(set) var state: PluginSupervisor.State = .stopped
    private(set) var menuBar: ViewNode?
    private(set) var panel: ViewNode?
    private(set) var problem: String?
    private(set) var logs: [String] = []

    @ObservationIgnored private var supervisor: PluginSupervisor?

    init(source: URL) {
        self.id = source.path
        self.source = source
        self.name = source.deletingPathExtension().lastPathComponent
    }

    /// Builds the plugin if it is a `.swift` file, then starts its helper.
    func load(builder: PluginBuilder, sandbox: Bool) async {
        state = .starting
        problem = nil
        let source = source
        do {
            let (supervisor, updates) = try await Task.detached {
                let binary = source.pathExtension == "swift" ? try builder.build(source: source).binary : source
                let manifest = try PluginProcess.readManifest(executable: binary)
                if sandbox {
                    try builder.sign(binary: binary, manifest: manifest)
                }
                let (updates, continuation) = AsyncStream.makeStream(of: PluginSupervisor.Update.self)
                let supervisor = PluginSupervisor(executable: binary, manifest: manifest) { continuation.yield($0) }
                return (supervisor, updates)
            }.value
            self.supervisor = supervisor
            name = supervisor.manifest.name
            // One consumer, so updates are applied in the order they happened.
            Task { [weak self] in
                for await update in updates {
                    self?.apply(update)
                }
            }
            await supervisor.start()
        } catch {
            state = .failed("could not start")
            problem = "\(error)"
        }
    }

    func send(_ action: ActionID, _ value: EventValue?) {
        Task { await supervisor?.event(action, value: value) }
    }

    func setPanelVisible(_ visible: Bool) {
        Task { await supervisor?.setVisible(.panel, visible) }
    }

    func refresh() {
        Task { await supervisor?.refresh() }
    }

    func wake() {
        Task { await supervisor?.wake() }
    }

    func restart() {
        Task {
            await supervisor?.stop()
            await supervisor?.start()
        }
    }

    private func apply(_ update: PluginSupervisor.Update) {
        switch update {
        case .state(let newState):
            state = newState
        case .render(.menuBar, let root):
            menuBar = root
        case .render(.panel, let root):
            panel = root
        case .log(let level, let message):
            logs.append("[\(level.rawValue)] \(message)")
            if logs.count > 200 { logs.removeFirst(logs.count - 200) }
        }
    }
}
#endif
