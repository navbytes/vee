import Foundation
import VeeProtocol
import VeeEngine

/// The launcher-side (peer) view of the JSON-RPC transport.
///
/// The `AppCoordinator` is a transport PEER, not a direct caller of the host's
/// render API (docs/ARCHITECTURE.md §3, the architect review). The host already
/// diffs each `vee.render` and writes a `plugin.render` notification toward the
/// launcher; the coordinator attaches to that inbound stream and sends host→plugin
/// frames back the other way. This narrow protocol captures exactly those two
/// directions so the coordinator depends on an abstraction (testable with a fake)
/// rather than on `LoopbackTransport`'s concrete `peerInbound`/`sendFromPeer`.
public protocol CoordinatorTransport: AnyObject {
    /// Install the handler invoked for each frame the host writes toward the
    /// launcher (`plugin.render`, `plugin.setCandidates`, `plugin.log`,
    /// `plugin.showToast`). Mirrors the `Recorder`'s `peerInbound` subscription.
    func attachInbound(_ handler: @escaping (JSONRPCMessage) -> Void)

    /// Send one frame from the launcher toward the host (`host.invokeAction`,
    /// `host.onSearchTextChange`, `host.submitForm`). Maps to the loopback's
    /// `sendFromPeer`.
    func sendToHost(_ message: JSONRPCMessage)
}

/// Adapts a `VeeEngine.LoopbackTransport` (the in-memory transport the host uses)
/// to the launcher's `CoordinatorTransport` half. The host attaches via
/// `onReceive` + `send`; the launcher attaches here via `peerInbound` and injects
/// with `sendFromPeer`, so the two ends share one ordered, codec-checked channel.
public final class LoopbackCoordinatorTransport: CoordinatorTransport {
    private let loopback: LoopbackTransport
    public init(_ loopback: LoopbackTransport) { self.loopback = loopback }

    public func attachInbound(_ handler: @escaping (JSONRPCMessage) -> Void) {
        loopback.peerInbound = handler
    }

    public func sendToHost(_ message: JSONRPCMessage) {
        loopback.sendFromPeer(message)
    }
}

// MARK: - Typed-payload outbound helper

extension CoordinatorTransport {
    /// Send a host→plugin notification carrying a typed, Encodable payload.
    func notify<P: Encodable>(method: String, params: P) {
        let value: JSONValue
        do {
            let data = try JSONEncoder().encode(params)
            value = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            value = .null
        }
        sendToHost(.notification(JSONRPCNotification(method: method, params: value)))
    }
}
