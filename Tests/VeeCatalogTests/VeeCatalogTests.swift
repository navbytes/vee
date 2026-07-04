import XCTest
@testable import VeeCatalog

final class CatalogParserTests: XCTestCase {
    private let treeJSON = """
    {"tree":[
      {"path":"System/CPU/cpu.5s.sh","type":"blob"},
      {"path":"System/README.md","type":"blob"},
      {"path":".github/workflows/ci.yml","type":"blob"},
      {"path":"Finance/stocks.1m.py","type":"blob"},
      {"path":"Finance","type":"tree"},
      {"path":"topfile.sh","type":"blob"}
    ]}
    """

    func testParsesPluginsAndFiltersNoise() throws {
        let entries = try CatalogParser.parse(treeJSON: Data(treeJSON.utf8))
        // Only the two real category plugins survive.
        XCTAssertEqual(entries.map(\.path), ["Finance/stocks.1m.py", "System/CPU/cpu.5s.sh"])
        let cpu = entries.first { $0.filename == "cpu.5s.sh" }!
        XCTAssertEqual(cpu.category, "System")
        XCTAssertEqual(cpu.rawURL.absoluteString, "https://raw.githubusercontent.com/matryer/xbar-plugins/main/System/CPU/cpu.5s.sh")
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try CatalogParser.parse(treeJSON: Data("nope".utf8)))
    }
}

final class PluginInstallerTests: XCTestCase {
    func testInstallWritesExecutableFile() throws {
        let dir = NSTemporaryDirectory() + "vee-install-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: dir) }

        XCTAssertFalse(PluginInstaller.isInstalled(filename: "x.5s.sh", in: dir))
        let path = try PluginInstaller.install(filename: "x.5s.sh", source: "#!/bin/bash\necho hi\n", into: dir)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path))
        XCTAssertTrue(PluginInstaller.isInstalled(filename: "x.5s.sh", in: dir))
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "#!/bin/bash\necho hi\n")
    }
}
