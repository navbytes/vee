import Foundation

/// JSON-RPC 2.0 envelope used on the host↔plugin transport.
///
/// We model the three message shapes explicitly (request / response /
/// notification) plus the error object, all `Codable`. `id` is a string or
/// integer per spec; we model it as an enum. `params`/`result` are `JSONValue`
/// so any method's payload round-trips without bespoke types here — the typed
/// payloads live in `RPCMethods` + the param/result structs below.

public enum JSONRPCID: Codable, Hashable, Sendable {
    case string(String)
    case number(Int)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { self = .number(i) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "id must be string or number") }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .string(let s): try c.encode(s); case .number(let i): try c.encode(i) }
    }
}

/// A method invocation expecting a response (`id` present).
public struct JSONRPCRequest: Codable, Hashable, Sendable {
    public let jsonrpc: String   // always "2.0"
    public var id: JSONRPCID
    public var method: String
    public var params: JSONValue?

    public init(id: JSONRPCID, method: String, params: JSONValue? = nil) {
        self.jsonrpc = "2.0"; self.id = id; self.method = method; self.params = params
    }
}

/// A one-way message with no response (`id` absent). Used for `plugin.render`,
/// `host.onSearchTextChange`, log streaming, etc.
public struct JSONRPCNotification: Codable, Hashable, Sendable {
    public let jsonrpc: String   // always "2.0"
    public var method: String
    public var params: JSONValue?

    public init(method: String, params: JSONValue? = nil) {
        self.jsonrpc = "2.0"; self.method = method; self.params = params
    }
}

public struct JSONRPCError: Codable, Hashable, Sendable, Error {
    public var code: Int
    public var message: String
    public var data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code; self.message = message; self.data = data
    }

    // Standard JSON-RPC 2.0 codes + Vee-specific reserved range (-32000…-32099).
    public static func parseError(_ m: String = "Parse error") -> JSONRPCError { .init(code: -32700, message: m) }
    public static func invalidRequest(_ m: String = "Invalid request") -> JSONRPCError { .init(code: -32600, message: m) }
    public static func methodNotFound(_ m: String) -> JSONRPCError { .init(code: -32601, message: "Method not found: \(m)") }
    public static func invalidParams(_ m: String = "Invalid params") -> JSONRPCError { .init(code: -32602, message: m) }
    public static func internalError(_ m: String = "Internal error") -> JSONRPCError { .init(code: -32603, message: m) }
    /// Vee: a plugin threw / rejected. `data` carries the JS stack when available.
    public static func pluginError(_ m: String, data: JSONValue? = nil) -> JSONRPCError { .init(code: -32000, message: m, data: data) }
    /// Vee: a bridge call was denied by the capability manifest.
    public static func capabilityDenied(_ m: String) -> JSONRPCError { .init(code: -32001, message: m) }
}

/// A response to a `JSONRPCRequest`. Exactly one of `result`/`error` is set.
public struct JSONRPCResponse: Codable, Hashable, Sendable {
    public let jsonrpc: String   // always "2.0"
    public var id: JSONRPCID?    // null id permitted only for pre-id parse errors
    public var result: JSONValue?
    public var error: JSONRPCError?

    public init(id: JSONRPCID?, result: JSONValue) {
        self.jsonrpc = "2.0"; self.id = id; self.result = result; self.error = nil
    }
    public init(id: JSONRPCID?, error: JSONRPCError) {
        self.jsonrpc = "2.0"; self.id = id; self.result = nil; self.error = error
    }
}

/// Untyped envelope for decoding an inbound frame whose kind is unknown until
/// inspected. Decode this first, then branch on `kind`.
public enum JSONRPCMessage: Sendable {
    case request(JSONRPCRequest)
    case notification(JSONRPCNotification)
    case response(JSONRPCResponse)

    public init(data: Data, decoder: JSONDecoder = JSONDecoder()) throws {
        // Response is distinguished by presence of `result` or `error`;
        // request vs notification by presence of `id`.
        if let r = try? decoder.decode(JSONRPCResponse.self, from: data),
           (r.result != nil || r.error != nil) {
            self = .response(r); return
        }
        if let req = try? decoder.decode(JSONRPCRequest.self, from: data) {
            self = .request(req); return
        }
        if let note = try? decoder.decode(JSONRPCNotification.self, from: data) {
            self = .notification(note); return
        }
        throw JSONRPCError.parseError("unrecognized JSON-RPC frame")
    }
}
