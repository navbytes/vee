import XCTest
@testable import vee
import VeeProtocol

/// R2-HIGH-3 (plugin authenticity): discovery must not let a second manifest
/// claim an id that's already taken — that's the vector by which a spoofed/
/// duplicate plugin would shadow another and reach its Keychain namespace. These
/// exercise the dev-tree path (`<root>/plugins/samples/*/vee.json` paired with
/// `<root>/plugins/fixtures/<id>.bundle.js`); `Bundle.main` in the test runner has
/// no `vee-plugins`, so discovery falls back to it.
final class PluginDiscoveryTests: XCTestCase {

    private func makeDevTree(_ plugins: [(folder: String, id: String)]) throws -> String {
        let fm = FileManager.default
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("veecli-\(UUID().uuidString)")
        let samples = (root as NSString).appendingPathComponent("plugins/samples")
        let fixtures = (root as NSString).appendingPathComponent("plugins/fixtures")
        try fm.createDirectory(atPath: samples, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: fixtures, withIntermediateDirectories: true)
        for p in plugins {
            let dir = (samples as NSString).appendingPathComponent(p.folder)
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let manifest = """
            {"id":"\(p.id)","name":"\(p.folder)","version":"1","entrypoint":"x",\
            "commands":[{"name":"view","title":"View","mode":"view"}],"capabilities":{}}
            """
            try manifest.write(toFile: (dir as NSString).appendingPathComponent("vee.json"),
                               atomically: true, encoding: .utf8)
            try "/* bundle */".write(
                toFile: (fixtures as NSString).appendingPathComponent("\(p.id).bundle.js"),
                atomically: true, encoding: .utf8)
        }
        return root
    }

    func testRefusesDuplicatePluginId() throws {
        let root = try makeDevTree([("alpha", "com.vee.dup"), ("beta", "com.vee.dup")])
        defer { try? FileManager.default.removeItem(atPath: root) }
        let found = PluginDiscovery.discoverAll(currentDirectory: root)
        XCTAssertEqual(found.map(\.manifest.id), ["com.vee.dup"],
                       "a second manifest claiming an existing id must be refused (R2-HIGH-3)")
    }

    func testDiscoversDistinctIdsSortedById() throws {
        let root = try makeDevTree([("b", "com.vee.bbb"), ("a", "com.vee.aaa")])
        defer { try? FileManager.default.removeItem(atPath: root) }
        let found = PluginDiscovery.discoverAll(currentDirectory: root)
        XCTAssertEqual(found.map(\.manifest.id), ["com.vee.aaa", "com.vee.bbb"])
    }
}
