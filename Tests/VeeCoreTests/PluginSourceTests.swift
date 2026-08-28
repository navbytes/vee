import XCTest
@testable import VeeCore

/// A plugin file is a script someone wrote in whatever editor they had, not a
/// guaranteed-UTF-8 document. Reading it strictly turned one bad byte into an
/// empty header — no declared variables (so the plugin's configured values,
/// Keychain secrets included, silently vanished from its environment), no
/// schedule, and a trust level indistinguishable from "declared nothing" —
/// while the plugin itself kept running fine, because the executor reads bytes
/// through its own `FileHandle`.
final class PluginSourceTests: XCTestCase {
    private func write(_ data: Data) -> String {
        let path = NSTemporaryDirectory() + "vee-source-" + UUID().uuidString
        FileManager.default.createFile(atPath: path, contents: data)
        return path
    }

    func testReadsValidUTF8Unchanged() {
        let source = "#!/bin/bash\n# <xbar.var>string(API_KEY=\"\"): Token</xbar.var>\necho hi\n"
        let path = write(Data(source.utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertEqual(PluginSource.read(atPath: path), source)
    }

    func testUndecodableByteDoesNotVoidTheRestOfTheFile() {
        // 0xE9 is `é` in Latin-1 and is not valid UTF-8 — one of these in a
        // comment used to void the whole header.
        var data = Data("#!/bin/bash\n# caf".utf8)
        data.append(0xE9)
        data.append(contentsOf: Data("\n# <xbar.var>string(API_KEY=\"\"): Token</xbar.var>\necho hi\n".utf8))

        let path = write(data)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let source = PluginSource.read(atPath: path)
        XCTAssertNotNil(source)
        XCTAssertTrue(source?.contains("<xbar.var>string(API_KEY=\"\"): Token</xbar.var>") == true,
                      "the declaration after the bad byte must still be there to parse")
        XCTAssertTrue(source?.contains("\u{FFFD}") == true, "the undecodable byte becomes the replacement character")
    }

    func testMissingFileIsNil() {
        XCTAssertNil(PluginSource.read(atPath: NSTemporaryDirectory() + "vee-does-not-exist-" + UUID().uuidString),
                     "unreadable is a genuinely different condition from not-valid-UTF-8, and stays reportable")
    }
}
