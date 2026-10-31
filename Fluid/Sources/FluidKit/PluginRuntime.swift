/// Runs one plugin against the host's messages.
///
/// Messages are handled strictly in order, one at a time, so plugin code never
/// runs concurrently with itself and needs no locking: a refresh finishes
/// before the click that arrived during it is handled. The cost is that a slow
/// `refresh()` delays events; plugins should keep refreshes short.
@MainActor
public final class PluginRuntime {
    public typealias Send = @Sendable (PluginMessage) -> Void

    private let plugin: any FluidPlugin
    private let send: Send
    private var surfaces: [Surface] = []
    private var lastSent: [Surface: ViewNode] = [:]
    private var handlers: [ActionID: RenderContext.Handler] = [:]

    public init(plugin: any FluidPlugin, send: @escaping Send) {
        self.plugin = plugin
        self.send = send
    }

    /// Handles one message; returns `false` once the plugin should exit.
    @discardableResult
    public func handle(_ message: HostMessage) async -> Bool {
        switch message {
        case .hello(_, let offered):
            let declared = type(of: plugin).manifest.surfaces
            surfaces = declared.filter(offered.contains)
            send(.ready(protocolVersion: FluidProtocolVersion.current))
            render()
        case .trigger:
            do {
                try await plugin.refresh()
            } catch {
                send(.log(level: .error, message: "refresh failed: \(error)"))
            }
            render()
        case .event(let action, let value):
            guard let handler = handlers[action] else {
                send(.log(level: .warning, message: "no handler for action \(action)"))
                send(.settled)
                return true
            }
            do {
                try await handler(value)
            } catch {
                send(.log(level: .error, message: "action \(action) failed: \(error)"))
            }
            render()
        case .visibility(let surface, let visible):
            if visible {
                // Re-send on open, so a host that dropped the tree recovers.
                lastSent[surface] = nil
                render()
            }
        case .shutdown:
            return false
        }
        send(.settled)
        return true
    }

    /// Resolves every surface and sends the ones that changed.
    public func render() {
        let context = RenderContext()
        for surface in surfaces {
            let content = surface == .menuBar ? plugin.menuBar : plugin.panel
            let root = Self.root(for: surface, content.resolve(in: context))
            if lastSent[surface] != root {
                lastSent[surface] = root
                send(.render(surface: surface, root: root))
            }
        }
        handlers = context.handlers
    }

    static func root(for surface: Surface, _ nodes: [ViewNode]) -> ViewNode {
        if nodes.count == 1 { return nodes[0] }
        return .stack(axis: surface == .menuBar ? .horizontal : .vertical, spacing: nil, children: nodes)
    }
}
