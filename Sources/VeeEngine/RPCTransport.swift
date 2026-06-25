import Foundation
import VeeProtocol

/// A bidirectional JSON-RPC 2.0 frame transport.
///
/// The host writes frames toward the launcher (notifications it originates, and
/// responses to inbound bridge requests) and receives frames from the launcher
/// (host→plugin notifications like `host.invokeAction`, lifecycle requests).
///
/// Frames stay ordered: the codec serializes encode/decode and delivery on a
/// single serial queue, matching the architecture's "serial queues and buffered
/// streams to make sure messages arrive and leave in order" requirement.
public protocol RPCTransport: AnyObject {
    /// Send one frame toward the peer (the launcher / app side).
    func send(_ message: JSONRPCMessage)

    /// Install the handler invoked for each frame arriving FROM the peer.
    /// Set by the host so it can route host→plugin notifications & lifecycle.
    var onReceive: ((JSONRPCMessage) -> Void)? { get set }
}

/// JSON-RPC 2.0 codec over the VeeProtocol envelopes. Pure value transforms;
/// the wire is newline-free single JSON objects (framing is the transport's job).
public enum RPCCodec {
    public static func encode(_ message: JSONRPCMessage) throws -> Data {
        let encoder = JSONEncoder()
        switch message {
        case .request(let r):      return try encoder.encode(r)
        case .notification(let n): return try encoder.encode(n)
        case .response(let r):     return try encoder.encode(r)
        }
    }

    public static func decode(_ data: Data) throws -> JSONRPCMessage {
        try JSONRPCMessage(data: data)
    }
}

/// In-memory loopback transport used by tests (and as a base for a real,
/// fd-backed transport later). The host attaches via `onReceive`; the test
/// (the "peer", i.e. the launcher) attaches via `peerInbound` and injects
/// inbound frames with `sendFromPeer`.
///
/// All delivery hops through one serial queue so ordering is deterministic and
/// matches production framing semantics. Encode/decode actually round-trips
/// through `RPCCodec` so the JSON-RPC 2.0 wire shape is exercised, not bypassed.
public final class LoopbackTransport: RPCTransport {
    public var onReceive: ((JSONRPCMessage) -> Void)?
    /// The peer (launcher/test) observes everything the host sends here.
    public var peerInbound: ((JSONRPCMessage) -> Void)?

    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<UInt8>()

    public init(label: String = "vee.engine.transport") {
        self.queue = DispatchQueue(label: label)
        self.queue.setSpecific(key: queueKey, value: 1)
    }

    /// Run `work` on the serial queue, but if we're ALREADY on it (a re-entrant
    /// call — e.g. a plugin emits `showToast` from inside an inbound
    /// `host.invokeAction` handler), run inline instead of `queue.sync`, which
    /// would deadlock/trap. Preserves ordering and synchronous delivery.
    private func onQueue(_ work: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            work()
        } else {
            queue.sync(execute: work)
        }
    }

    /// Host → peer. Round-trips through the codec to exercise real serialization,
    /// then delivers on the serial queue (synchronously, preserving order while
    /// keeping the call re-entrant-safe for the synchronous test driver).
    public func send(_ message: JSONRPCMessage) {
        // Round-trip through the JSON-RPC codec so we genuinely speak the wire
        // contract (a malformed frame would throw here, surfacing encoder bugs).
        let decoded: JSONRPCMessage
        do {
            let data = try RPCCodec.encode(message)
            decoded = try RPCCodec.decode(data)
        } catch {
            // An un-encodable host frame is a programmer error; drop loudly in
            // debug. Production transport would log + skip.
            assertionFailure("RPCCodec.encode/decode failed: \(error)")
            decoded = message
        }
        onQueue {
            self.peerInbound?(decoded)
        }
    }

    /// Peer → host. The test/launcher injects an inbound frame; it is delivered
    /// to the host's `onReceive` on the same serial queue.
    public func sendFromPeer(_ message: JSONRPCMessage) {
        let decoded: JSONRPCMessage
        do {
            let data = try RPCCodec.encode(message)
            decoded = try RPCCodec.decode(data)
        } catch {
            assertionFailure("RPCCodec encode/decode failed for inbound: \(error)")
            decoded = message
        }
        onQueue {
            self.onReceive?(decoded)
        }
    }
}

// MARK: - Encoding helpers for typed payloads → JSONValue

extension RPCTransport {
    /// Send a notification carrying a typed, Encodable payload.
    func notify<P: Encodable>(method: String, params: P) {
        let value = (try? JSONValueCoder.encode(params)) ?? .null
        send(.notification(JSONRPCNotification(method: method, params: value)))
    }
}

/// Bridges typed Codable payloads to/from the protocol's `JSONValue`.
enum JSONValueCoder {
    static func encode<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    static func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
