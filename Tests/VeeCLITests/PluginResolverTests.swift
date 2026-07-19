import XCTest
import VeeCore
@testable import VeeCLI

/// `PluginResolver` maps the `<plugin>` argument (a path or an installed name)
/// to a concrete file, tested against temporary directories.
final class PluginResolverTests: XCTestCase {
    private var pluginsDir = ""
    private var emptyDir = ""

    override func setUpWithError() throws {
        let base = NSTemporaryDirectory() as NSString
        pluginsDir = base.appendingPathComponent("vee-resolver-\(ProcessInfo.processInfo.globallyUniqueString)")
        emptyDir = base.appendingPathComponent("vee-empty-\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(atPath: pluginsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: emptyDir, withIntermediateDirectories: true)
        let file = (pluginsDir as NSString).appendingPathComponent("cpu.10s.sh")
        try "echo hi\n".write(toFile: file, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: pluginsDir)
        try? FileManager.default.removeItem(atPath: emptyDir)
    }

    func testResolvesByAbsolutePath() {
        let path = (pluginsDir as NSString).appendingPathComponent("cpu.10s.sh")
        let result = PluginResolver.resolve(argument: path, directory: emptyDir, currentDirectory: emptyDir)
        guard case .success(let resolved) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(resolved.path, path)
        XCTAssertEqual(resolved.displayName, "cpu")
        XCTAssertEqual(resolved.interval, .seconds(10))
    }

    func testResolvesByInstalledName() {
        let result = PluginResolver.resolve(argument: "cpu", directory: pluginsDir, currentDirectory: emptyDir)
        guard case .success(let resolved) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(resolved.displayName, "cpu")
        XCTAssertEqual(resolved.interval, .seconds(10))
        XCTAssertTrue(resolved.path.hasSuffix("cpu.10s.sh"), resolved.path)
    }

    func testUnknownNameReportsAvailable() {
        let result = PluginResolver.resolve(argument: "ghost", directory: pluginsDir, currentDirectory: emptyDir)
        guard case .failure(.nameNotFound(let name, let available)) = result else {
            return XCTFail("expected nameNotFound, got \(result)")
        }
        XCTAssertEqual(name, "ghost")
        XCTAssertEqual(available, ["cpu"])
    }

    func testMissingPathReportsFileNotFound() {
        let result = PluginResolver.resolve(argument: "./nope.sh", directory: pluginsDir, currentDirectory: emptyDir)
        guard case .failure(.fileNotFound) = result else {
            return XCTFail("expected fileNotFound, got \(result)")
        }
    }

    func testPluginsDirectoryPrefersExplicitOverride() {
        let dir = PluginResolver.pluginsDirectory(
            override: "/tmp/custom-plugins",
            environment: ["VEE_PLUGINS_DIR": "/env/dir"],
            defaults: UserDefaults.standard)
        XCTAssertEqual(dir, "/tmp/custom-plugins")
    }

    func testPluginsDirectoryFallsBackToEnv() {
        let dir = PluginResolver.pluginsDirectory(
            override: nil,
            environment: ["VEE_PLUGINS_DIR": "/env/dir"])
        XCTAssertEqual(dir, "/env/dir")
    }
}
