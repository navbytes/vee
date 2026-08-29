import XCTest
@testable import VeeCLI

/// Keeps the `vee new` TS/Python templates' inlined type blocks honest against
/// the published JSON output schema: every field name the template declares
/// (`interface`/`TypedDict`) must be a real schema property. A cheap
/// string-level check, not codegen — see openspec/changes/retire-plugin-sdks.
final class TemplateSchemaDriftTests: XCTestCase {
    private func schemaPropertyNames() throws -> Set<String> {
        // .../Tests/VeeCLITests/TemplateSchemaDriftTests.swift → repo root
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/schemas/json-output.schema.json")
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var names: Set<String> = []
        collectPropertyNames(json, into: &names)
        return names
    }

    /// Recurses through every `"properties"` object in the schema (including
    /// nested `$defs`), collecting the property keys.
    private func collectPropertyNames(_ node: Any, into names: inout Set<String>) {
        guard let dict = node as? [String: Any] else {
            if let array = node as? [Any] {
                for element in array { collectPropertyNames(element, into: &names) }
            }
            return
        }
        if let properties = dict["properties"] as? [String: Any] {
            names.formUnion(properties.keys)
        }
        for (_, value) in dict { collectPropertyNames(value, into: &names) }
    }

    /// Field names declared in the template's inlined type block: an
    /// indented `key: type` or `key?: type` line (interface/TypedDict field
    /// syntax in both languages), excluding top-level statements.
    private func declaredKeys(in contents: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: #"^[ \t]+([A-Za-z_][A-Za-z0-9_]*)\??:\s"#, options: [.anchorsMatchLines]) else {
            XCTFail("invalid regex")
            return []
        }
        let range = NSRange(contents.startIndex..., in: contents)
        var keys: Set<String> = []
        regex.enumerateMatches(in: contents, range: range) { match, _, _ in
            guard let match, let r = Range(match.range(at: 1), in: contents) else { return }
            keys.insert(String(contents[r]))
        }
        return keys
    }

    func testTSTemplateTypeBlockMatchesSchema() throws {
        let schema = try schemaPropertyNames()
        let (_, contents) = Scaffold.render(lang: .ts, interval: "10s", name: "Example", trust: [])
        let keys = declaredKeys(in: contents)
        XCTAssertFalse(keys.isEmpty)
        XCTAssertTrue(keys.isSubset(of: schema), "not in schema: \(keys.subtracting(schema))")
    }

    func testPythonTemplateTypeBlockMatchesSchema() throws {
        let schema = try schemaPropertyNames()
        let (_, contents) = Scaffold.render(lang: .py, interval: "10s", name: "Example", trust: [])
        let keys = declaredKeys(in: contents)
        XCTAssertFalse(keys.isEmpty)
        XCTAssertTrue(keys.isSubset(of: schema), "not in schema: \(keys.subtracting(schema))")
    }
}
