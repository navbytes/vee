import Foundation
import JavaScriptCore
import VeeProtocol

/// Lossless conversion between `JSValue` and the protocol's `JSONValue`.
///
/// We route through the JS engine's own `JSON.stringify`/`JSON.parse` for total
/// fidelity with what the plugin sees (key ordering, number coercion, nested
/// structures) rather than walking `JSValue` by hand — JSC's serializer is the
/// source of truth for the wire projection, and a `RenderNode` produced by the
/// SDK is already a plain JSON object by the time `vee.render` receives it.
///
/// IMPORTANT (memory rule a): these are static and take an explicit context;
/// they never capture a context in a stored closure.
enum JSONBridge {
    /// JS value → JSONValue. Returns nil only if serialization genuinely fails
    /// (e.g. a value with a circular reference). `undefined` maps to `.null`.
    static func toJSONValue(_ value: JSValue) -> JSONValue? {
        if value.isUndefined || value.isNull { return .null }
        guard let ctx = value.context else { return nil }
        let stringify = ctx.evaluateScript("(function(x){ return JSON.stringify(x); })")!
        guard let jsonString = stringify.call(withArguments: [value])?.toString(),
              jsonString != "undefined",
              let data = jsonString.data(using: .utf8) else {
            return .null
        }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// JSONValue → JS value, parsed in `ctx` so it's a genuine JS object/array.
    static func toJSValue(_ value: JSONValue, in ctx: JSContext) -> JSValue {
        switch value {
        case .null:
            return JSValue(nullIn: ctx)
        case .bool(let b):
            return JSValue(bool: b, in: ctx)
        case .number(let d):
            return JSValue(double: d, in: ctx)
        case .string(let s):
            return JSValue(object: s, in: ctx)
        case .array, .object:
            // Round-trip through JSON.parse for a real nested JS structure.
            guard let data = try? JSONEncoder().encode(value),
                  let jsonString = String(data: data, encoding: .utf8) else {
                return JSValue(nullIn: ctx)
            }
            let parse = ctx.evaluateScript("(function(s){ return JSON.parse(s); })")!
            return parse.call(withArguments: [jsonString]) ?? JSValue(nullIn: ctx)
        }
    }
}
