import XCTest
@testable import VeeCatalog
import VeeCore

/// A plugin installed on its own must land beside the SDK it imports.
///
/// A Vee plugin is a single file with no build step, so its SDK travels as a
/// sibling (`vee.py` / `vee.ts`). The plugin repository checks that file in
/// beside the plugins and `vee new` writes both, but the two paths that
/// install *one* file — Discover's Install button and `addplugin` deep links —
/// wrote only the plugin. Every run of it then died with
/// `ModuleNotFoundError: No module named 'vee'`: a traceback in the menu bar,
/// for something the user did nothing to cause.
final class InstallVendorsSDKTests: XCTestCase {
    private var dir: String = ""

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vee-install-\(UUID().uuidString)", isDirectory: true).path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: dir)
    }

    private func path(_ name: String) -> String { (dir as NSString).appendingPathComponent(name) }
    private func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: path(name)) }

    /// The regression, in the exact shape it was reported: install `github.5m.py`
    /// into an empty directory and it must be able to import the SDK.
    func testPythonPluginImportingTheSDKGetsItVendored() throws {
        let source = "#!/usr/bin/env python3\n# <vee.title>GitHub</vee.title>\nfrom vee import JSONMenu\nprint('x')\n"
        try PluginInstaller.install(filename: "github.5m.py", source: source, into: dir)

        XCTAssertTrue(exists("vee.py"), "a plugin that imports the SDK must be installed beside it")
        let vendored = try String(contentsOfFile: path("vee.py"), encoding: .utf8)
        XCTAssertEqual(vendored, EmbeddedSDK.source(for: "python"), "the vendored copy must be the embedded SDK verbatim")
    }

    func testBareImportFormIsRecognised() throws {
        try PluginInstaller.install(filename: "thing.1m.py", source: "#!/usr/bin/env python3\nimport vee\n", into: dir)
        XCTAssertTrue(exists("vee.py"), "`import vee` reaches the SDK just as `from vee import …` does")
    }

    func testTypeScriptPluginImportingTheVendoredSDKGetsIt() throws {
        let source = "#!/usr/bin/env -S node --experimental-strip-types\nimport { Menu } from './vee.ts'\n"
        try PluginInstaller.install(filename: "cost.90s.ts", source: source, into: dir)
        XCTAssertTrue(exists("vee.ts"))
        XCTAssertFalse(exists("vee.py"), "only the language actually imported is vendored")
    }

    /// Most plugins vendor nothing. Writing a 34 KB SDK next to every script
    /// someone installs would litter the directory with an unasked-for
    /// dependency.
    func testPluginThatDoesNotImportTheSDKGetsNothingExtra() throws {
        let source = "#!/usr/bin/env python3\nprint('Hello | color=green')\n"
        try PluginInstaller.install(filename: "plain.5m.py", source: source, into: dir)
        XCTAssertFalse(exists("vee.py"), "a plugin that prints the text format directly needs no SDK")
    }

    /// A comment mentioning vee, or a local name that merely starts with it,
    /// is not an import.
    func testMentionOfVeeIsNotAnImport() throws {
        let source = "#!/usr/bin/env python3\n# built for vee; see import vee docs\nvee_count = 1\nprint(vee_count)\n"
        try PluginInstaller.install(filename: "mentions.5m.py", source: source, into: dir)
        XCTAssertFalse(exists("vee.py"))
    }

    /// A directory that already has an SDK is one someone else is curating —
    /// the plugin repository's own checked-in copy, or a newer one a previous
    /// install vendored. Replacing it could break the plugins already using it.
    func testExistingSDKIsNeverOverwritten() throws {
        let mine = "# my own copy\n"
        try mine.write(toFile: path("vee.py"), atomically: true, encoding: .utf8)
        try PluginInstaller.install(filename: "github.5m.py", source: "from vee import JSONMenu\n", into: dir)
        XCTAssertEqual(try String(contentsOfFile: path("vee.py"), encoding: .utf8), mine,
                       "an SDK already on disk must be left exactly as it was")
    }

    /// Vendoring is best-effort: the plugin is what the user asked for, and a
    /// companion that cannot be written must not fail the install or leave the
    /// plugin unwritten.
    func testPluginIsStillInstalledWhenTheSDKCannotBeWritten() throws {
        let sdkDir = path("vee.py")  // a directory where the SDK file would go
        try FileManager.default.createDirectory(atPath: sdkDir, withIntermediateDirectories: true)
        let installed = try PluginInstaller.install(filename: "github.5m.py", source: "from vee import JSONMenu\n", into: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed), "the plugin itself must still be installed")
    }

    /// Go plugins are compiled binaries that import the module, so there is no
    /// sibling to vendor.
    func testGoAndUnknownExtensionsVendorNothing() {
        XCTAssertNil(PluginInstaller.sdkLanguage(forPlugin: "thing.1m.go", source: "import \"github.com/navbytes/vee/plugins/go\""))
        XCTAssertNil(PluginInstaller.sdkLanguage(forPlugin: "thing.1m.sh", source: "from vee import Menu"))
    }
}
