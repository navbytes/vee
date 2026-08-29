import Foundation
import XCTest
@testable import VeeRuntime

/// The official SDK is retired, but a plugin folder may still carry a
/// historical `vee.ts`/`vee.py` sibling from when `vee new`/`vee sdk` vendored
/// it beside a plugin. That sibling lands in the same folder Vee scans, and
/// `vee.ts`/`vee.py` are otherwise valid plugin filenames — name `vee`, manual
/// interval — so discovery has to know they are not plugins.
final class PluginDiscoveryVendoredSDKTests: XCTestCase {
    private var directory: String!

    override func setUpWithError() throws {
        directory = NSTemporaryDirectory().appending("vee-discovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: directory)
    }

    private func write(_ name: String, executable: Bool = false) throws {
        let path = (directory as NSString).appendingPathComponent(name)
        try "#!/usr/bin/env node\n".write(toFile: path, atomically: true, encoding: .utf8)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }
    }

    private func discovered() -> [String] {
        PluginDiscovery.enabled(directory: directory)
            .map { ($0.path as NSString).lastPathComponent }
            .sorted()
    }

    func testVendoredSDKIsNotAPlugin() throws {
        try write("cpu.10s.ts", executable: true)
        try write("vee.ts")
        try write("vee.py")
        try write("vee.js")
        // Without the skip these run as plugins, exit non-zero, and surface as
        // broken menu-bar rows beside the plugins they exist to support.
        XCTAssertEqual(discovered(), ["cpu.10s.ts"])
    }

    func testAPluginWhoseNameMerelyStartsWithVeeStillLoads() throws {
        // The skip is by exact filename, not a prefix: a real plugin called
        // `vee-status.5m.ts` has nothing to do with the vendored SDK.
        try write("vee-status.5m.ts", executable: true)
        try write("veeble.10s.py", executable: true)
        XCTAssertEqual(discovered(), ["vee-status.5m.ts", "veeble.10s.py"])
    }

    func testNonExecutablePluginsAreStillLoaded() throws {
        // Vee runs plugins without the execute bit bash-wrapped, matching
        // SwiftBar; the SDK skip must not quietly change that.
        try write("notes.1h.sh")
        XCTAssertEqual(discovered(), ["notes.1h.sh"])
    }

    /// `ignoredExtensions` can't reach a file with no extension, so a plugins
    /// folder kept under version control — a habit the docs encourage — used to
    /// run its own README and Makefile through `/bin/bash` and show them as
    /// broken menu-bar rows.
    func testExtensionlessDocumentationAndBuildFilesAreNotPlugins() throws {
        try write("cpu.10s.sh", executable: true)
        try write("README")
        try write("LICENSE")
        try write("Makefile")
        try write("Dockerfile")
        XCTAssertEqual(discovered(), ["cpu.10s.sh"])
    }

    func testAPluginNamedLikeADocumentButWithAnExtensionStillLoads() throws {
        // The skip is by exact bare filename: `readme.10s.sh` is a plugin
        // someone named after what it reports, not documentation.
        try write("readme.10s.sh", executable: true)
        XCTAssertEqual(discovered(), ["readme.10s.sh"])
    }
}
