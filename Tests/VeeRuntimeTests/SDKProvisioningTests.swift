import XCTest
@testable import VeeRuntime
import VeeCore

/// Vee puts the SDK on each plugin's import path, so a plugin that imports it
/// runs without a copy sitting beside it.
///
/// These tests run the real interpreters. The whole design rests on how Python
/// and Node actually resolve — script directory before `PYTHONPATH`, `NODE_PATH`
/// ignored for ESM, `NODE_OPTIONS` split on whitespace — and asserting against
/// a model of that rather than the thing itself would be asserting my own
/// assumptions back at me.
final class SDKProvisioningTests: XCTestCase {
    private var root = ""
    private var plugins = ""

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("vee-sdk-\(UUID().uuidString)", isDirectory: true)
        // A space, because the real support directory is `Application Support`
        // and `NODE_OPTIONS` is whitespace-split — a raw path silently breaks.
        root = base.appendingPathComponent("Application Support/sdk").path
        plugins = base.appendingPathComponent("my plugins").path
        try FileManager.default.createDirectory(atPath: plugins, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: (root as NSString).deletingLastPathComponent)
    }

    private func write(_ contents: String, _ name: String) throws -> String {
        let path = (plugins as NSString).appendingPathComponent(name)
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    /// Runs `launch` under the environment Vee would give a plugin.
    private func runUnderVeeEnvironment(_ launch: String, _ args: [String]) throws -> String {
        let provisioned = try XCTUnwrap(SDKProvisioner.provision(into: root))
        let env = SDKProvisioner.apply(to: ProcessInfo.processInfo.environment, root: provisioned)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch)
        process.arguments = args
        process.environment = env
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Provisioning

    func testProvisionWritesBothSDKsAndTheResolver() throws {
        let provisioned = try XCTUnwrap(SDKProvisioner.provision(into: root))
        XCTAssertEqual(provisioned, root)
        for path in [SDKProvisioner.pythonPath(in: root) + "/vee.py",
                     SDKProvisioner.typescriptPath(in: root),
                     (root as NSString).appendingPathComponent("node/\(SDKProvisioner.resolverName)")] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), "missing \(path)")
        }
        XCTAssertEqual(try String(contentsOfFile: SDKProvisioner.pythonPath(in: root) + "/vee.py", encoding: .utf8),
                       EmbeddedSDK.source(for: "python"))
    }

    /// An upgraded Vee must serve its own SDK, not whatever the previous build
    /// left behind.
    func testProvisionRefreshesAStaleCopy() throws {
        SDKProvisioner.provision(into: root)
        let pythonSDK = SDKProvisioner.pythonPath(in: root) + "/vee.py"
        try "# an older build's copy\n".write(toFile: pythonSDK, atomically: true, encoding: .utf8)
        SDKProvisioner.provision(into: root)
        XCTAssertEqual(try String(contentsOfFile: pythonSDK, encoding: .utf8), EmbeddedSDK.source(for: "python"))
    }

    // MARK: - Environment shape

    func testInjectionExtendsRatherThanReplaces() {
        let base = ["PYTHONPATH": "/my/libs", "NODE_OPTIONS": "--max-old-space-size=4096"]
        let env = SDKProvisioner.apply(to: base, root: root)
        XCTAssertEqual(env["PYTHONPATH"], "\(SDKProvisioner.pythonPath(in: root)):/my/libs",
                       "Vee's entry is the fallback; the user's own path must survive and keep winning")
        let options = try? XCTUnwrap(env["NODE_OPTIONS"])
        XCTAssertTrue(options?.hasSuffix("--max-old-space-size=4096") == true, "a plugin's own NODE_OPTIONS must survive")
        XCTAssertTrue(options?.contains("--import file://") == true, "the resolver is loaded as a file URL")
    }

    /// `NODE_OPTIONS` is whitespace-split, and the real directory is
    /// `Application Support`. A raw path would break on the space.
    func testNodeImportIsAPercentEncodedURL() throws {
        let url = try XCTUnwrap(SDKProvisioner.nodeImportURL(in: root))
        XCTAssertTrue(url.hasPrefix("file://"))
        XCTAssertFalse(url.contains(" "), "a space in NODE_OPTIONS silently truncates the flag")
        XCTAssertTrue(url.contains("%20"), "the space in Application Support must be encoded")
    }

    func testNoSDKDirectoryInjectsNothing() {
        let ctx = RuntimeEnvironmentContext(
            pluginPath: "/p/x.py", pluginsDirectory: "/p", cacheDirectory: "/c", dataDirectory: "/d",
            isDarkMode: false, osVersion: (26, 0, 0), appVersion: "0.0.0")
        let env = EnvironmentBuilder.merged(base: [:], context: ctx)
        XCTAssertNil(env["PYTHONPATH"])
        XCTAssertNil(env["NODE_OPTIONS"])
    }

    // MARK: - The real interpreters

    /// The reported bug, in the shape it was reported: a plugin installed on
    /// its own, importing the SDK, with nothing beside it.
    func testPythonPluginImportsTheSDKWithNoSiblingPresent() throws {
        let plugin = try write("from vee import Menu\nm = Menu()\nm.title('ok', color='green')\nm.print()\n", "solo.5m.py")
        let output = try runUnderVeeEnvironment("/usr/bin/env", ["python3", plugin])
        XCTAssertTrue(output.contains("ok"), "expected the SDK to resolve; got: \(output)")
    }

    /// Precedence is what makes this safe: a folder that vendors its own SDK
    /// keeps using it, so a plugin repository's checked-in copy and an author
    /// pinning a version are both unaffected.
    func testAVendoredCopyStillWins() throws {
        _ = try write("class Menu:\n    def title(self, *a, **k): pass\n    def print(self): print('local copy won')\n", "vee.py")
        let plugin = try write("from vee import Menu\nMenu().print()\n", "solo.5m.py")
        let output = try runUnderVeeEnvironment("/usr/bin/env", ["python3", plugin])
        XCTAssertTrue(output.contains("local copy won"), "the sibling must take precedence; got: \(output)")
    }

    /// The import that could not be fixed by writing a file: a bare specifier
    /// names a package, and a plugins folder has no node_modules.
    func testNodePluginImportsTheSDKByPackageName() throws {
        guard let node = ["/opt/homebrew/bin/node", "/usr/local/bin/node"].first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { throw XCTSkip("node is not installed on this machine") }
        let plugin = try write("import { Menu } from '@navbytes/vee';\nconst m = new Menu();\nm.title('ok', { color: 'green' });\nm.print();\n", "solo.90s.mjs")
        let output = try runUnderVeeEnvironment(node, [plugin])
        XCTAssertTrue(output.contains("ok"), "expected @navbytes/vee to resolve; got: \(output)")
    }
}
