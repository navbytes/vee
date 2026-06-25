import XCTest
@testable import VeeProtocol

/// Real round-trip tests for the frozen wire contract (build plan §4,
/// VeeProtocol). These prove the wire format encodes/decodes exactly as
/// intended; the contract is frozen after these pass.
final class VeeProtocolTests: XCTestCase {

    // 1. Nested RenderNode encodes → decodes back equal.
    func testRenderNodeCodableRoundTrip() throws {
        let tree = RenderNode(tag: RenderNode.Tag.list, children: [
            RenderNode(tag: RenderNode.Tag.listItem, key: "a",
                       props: ["title": "Alpha", "subtitle": "first"]),
            RenderNode(tag: RenderNode.Tag.listItem, key: "b",
                       props: ["title": "Beta"]),
        ])
        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(RenderNode.self, from: data)
        XCTAssertEqual(decoded, tree)
    }

    // 2. RenderNode.jsonValue projection round-trips; nil key is omitted.
    func testRenderNodeJSONValueProjection() throws {
        let node = RenderNode(tag: RenderNode.Tag.detail, props: ["md": "# Hi"])
        let jv = node.jsonValue
        XCTAssertNil(jv["key"], "nil key must not appear in the projection")
        let back = try RenderNode(jsonValue: jv)
        XCTAssertEqual(back, node)

        let keyed = RenderNode(tag: "x", key: "k1")
        XCTAssertEqual(keyed.jsonValue["key"]?.stringValue, "k1")
    }

    // 3. JSONValue round-trips losslessly through encode→decode.
    func testJSONValueRoundTrip() throws {
        let json = #"{"a":1,"b":[true,null,"x"],"c":1.5}"#.data(using: .utf8)!
        let v = try JSONDecoder().decode(JSONValue.self, from: json)
        XCTAssertEqual(v["a"]?.intValue, 1)
        XCTAssertEqual(v["b"]?.arrayValue, [.bool(true), .null, .string("x")])
        XCTAssertEqual(v["c"]?.doubleValue, 1.5)

        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let reencoded = try enc.encode(v)
        let v2 = try JSONDecoder().decode(JSONValue.self, from: reencoded)
        XCTAssertEqual(v, v2, "encode→decode must be lossless")
    }

    // 4. PatchOp omits nil operands (encodeIfPresent).
    func testPatchOpEncodingOmitsNilOperands() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let removeStr = String(data: try enc.encode(PatchOp.remove("/a")), encoding: .utf8)!
        XCTAssertTrue(removeStr.contains("\"op\":\"remove\""))
        XCTAssertFalse(removeStr.contains("value"))
        XCTAssertFalse(removeStr.contains("from"))

        let moveStr = String(data: try enc.encode(PatchOp.move(from: "/a", to: "/b")), encoding: .utf8)!
        XCTAssertTrue(moveStr.contains("\"from\":\"/a\""))
        XCTAssertFalse(moveStr.contains("value"))
    }

    // 5. JSONRPCMessage classifies frames correctly; garbage throws.
    func testJSONRPCMessageClassification() throws {
        let response = #"{"jsonrpc":"2.0","id":1,"result":{"ok":true}}"#.data(using: .utf8)!
        guard case .response = try JSONRPCMessage(data: response) else {
            return XCTFail("expected response")
        }
        let request = #"{"jsonrpc":"2.0","id":1,"method":"foo","params":{}}"#.data(using: .utf8)!
        guard case .request = try JSONRPCMessage(data: request) else {
            return XCTFail("expected request")
        }
        let notification = #"{"jsonrpc":"2.0","method":"foo","params":{}}"#.data(using: .utf8)!
        guard case .notification = try JSONRPCMessage(data: notification) else {
            return XCTFail("expected notification")
        }
        let garbage = #"{"foo":1}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONRPCMessage(data: garbage))
    }

    // 6. JSONRPCID round-trips both string and number.
    func testJSONRPCIDRoundTrip() throws {
        for id in [JSONRPCID.string("x"), JSONRPCID.number(7)] {
            let data = try JSONEncoder().encode(id)
            XCTAssertEqual(try JSONDecoder().decode(JSONRPCID.self, from: data), id)
        }
    }

    // 7. Capability network allowlist: exact + dot-suffix wildcard.
    func testCapabilityNetworkAllowlist() {
        let exact = Capabilities(network: ["api.github.com"])
        XCTAssertTrue(exact.allowsNetworkHost("api.github.com"))
        XCTAssertFalse(exact.allowsNetworkHost("evil.com"))

        let wildcard = Capabilities(network: [".github.com"])
        XCTAssertTrue(wildcard.allowsNetworkHost("api.github.com"))
        XCTAssertTrue(wildcard.allowsNetworkHost("github.com"))
        XCTAssertFalse(wildcard.allowsNetworkHost("notgithub.com"))

        XCTAssertFalse(Capabilities().allowsNetworkHost("anything.com"), "empty allowlist denies")
    }

    // 8. RenderNode(jsonValue:) rejects malformed input.
    func testRenderNodeFromJSONValueRejectsMalformed() {
        XCTAssertThrowsError(try RenderNode(jsonValue: .object(["props": .object([:])]))) { error in
            XCTAssertEqual(error as? RenderNodeError, .malformed("expected object with string `tag`"))
        }
        XCTAssertThrowsError(try RenderNode(jsonValue: .object(["tag": "list", "props": .string("x")]))) { error in
            XCTAssertEqual(error as? RenderNodeError, .malformed("`props` must be an object"))
        }
    }
}
