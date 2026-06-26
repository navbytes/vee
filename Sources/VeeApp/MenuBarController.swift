import Foundation
import VeeProtocol
import VeeJSONPatch

/// Drives PLUGIN-OWNED menu-bar commands — Vee's analogue of a Raycast menu-bar
/// command.
///
/// A `mode: "menu-bar"` command runs in the background (activated at startup,
/// refreshed on its `refreshIntervalSeconds`) and renders into its OWN
/// `NSStatusItem` rather than the launcher window. This controller is the menu-bar
/// counterpart of `AppCoordinator`: for each registered menu-bar plugin it keeps a
/// private render mirror, applies inbound `plugin.render` patches (via
/// `VeeJSONPatch`), projects the tree to a status-item title/icon + dropdown
/// (`ViewModelProjector.menuBar`), and pushes it to the `PluginMenuBarPresenting`
/// seam. A dropdown selection is sent back to the plugin as exactly one
/// `host.invokeAction` frame.
///
/// Frames reach it via the launcher coordinator's demux (`AppCoordinator` forwards
/// frames whose `pluginId` is a registered menu-bar command), so the app keeps a
/// single inbound transport subscriber. No AppKit here — the seam is a protocol,
/// so this is fully unit-testable against a fake presenter + a recording transport.
///
/// Non-isolated, like `AppCoordinator`: it is driven on the main thread in
/// production (frames are delivered there and the refresh timer fires there), and
/// reaches the `@MainActor` AppKit presenter through the non-isolated seam.
public final class MenuBarController: MenuBarRouting {
    private let presenter: PluginMenuBarPresenting
    private let transport: CoordinatorTransport

    /// Per-plugin render mirror + last applied revision (the coordinator's pattern,
    /// one independent stream per menu-bar command).
    private struct MirrorState {
        var mirror: JSONValue?
        var lastRevision: Int = 0
    }
    private var states: [String: MirrorState] = [:]

    public init(presenter: PluginMenuBarPresenting, transport: CoordinatorTransport) {
        self.presenter = presenter
        self.transport = transport
    }

    /// Begin tracking a menu-bar plugin so its frames are accepted. Idempotent.
    /// (The coordinator must ALSO `registerMenuBarPlugin(_:)` so frames get demuxed
    /// here in the first place.)
    public func register(pluginId: String) {
        if states[pluginId] == nil { states[pluginId] = MirrorState() }
    }

    /// Stop tracking a menu-bar plugin and remove its status item.
    public func unregister(pluginId: String) {
        states[pluginId] = nil
        presenter.remove(pluginId: pluginId)
    }

    // MARK: - MenuBarRouting

    public func handleFrame(_ message: JSONRPCMessage) {
        guard case .notification(let note) = message, let params = note.params,
              let pid = params["pluginId"]?.stringValue, states[pid] != nil else { return }
        switch note.method {
        case RPCMethods.render:
            if let p = try? decode(RenderParams.self, from: params) { applyRender(pid, p) }
        default:
            // Menu-bar commands drive their surface via `plugin.render`; other
            // frames (setCandidates / log / toast) have no status-item surface.
            break
        }
    }

    // MARK: - Render application (mirror → patch → project → present)

    private func applyRender(_ pid: String, _ params: RenderParams) {
        var state = states[pid] ?? MirrorState()
        // Drop stale / out-of-order frames (monotonic revision, like the launcher).
        guard params.revision > state.lastRevision else { return }
        let base = state.mirror ?? .null
        guard let next = try? JSONPatch.apply(params.patch, to: base) else {
            // Desync recovery (mirror of the launcher's R2-MED-3 reset): drop the
            // mirror + revision so the host's next full-tree keyframe re-syncs
            // cleanly from `.null` instead of mis-applying diffs onto a stale base.
            state.mirror = nil
            state.lastRevision = 0
            states[pid] = state
            return
        }
        state.mirror = next
        state.lastRevision = params.revision
        states[pid] = state

        guard let node = try? RenderNode(jsonValue: next) else { return }
        let projection = ViewModelProjector.menuBar(from: node)
        presenter.upsert(
            pluginId: pid,
            title: projection.title,
            iconSymbol: projection.icon,
            items: projection.items
        ) { [weak self] actionId in
            // A dropdown selection → exactly one host.invokeAction back to the plugin.
            self?.transport.notify(
                method: RPCMethods.invokeAction,
                params: InvokeActionParams(pluginId: pid, actionId: actionId))
        }
    }

    // MARK: - Helpers

    private func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
