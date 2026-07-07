import XCTest
@testable import VeeWidgetShared

/// Covers `WidgetActionRequest`'s encode/decode round trip and
/// `WidgetActionRequestStore`'s write/read-clear semantics — the per-plugin
/// refresh/shortcut request channel a widget card's action buttons use.
final class WidgetActionRequestTests: XCTestCase {
    private func makeTempStore() -> (WidgetActionRequestStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vee-widget-action-\(UUID().uuidString)", isDirectory: true)
        return (WidgetActionRequestStore(directory: dir), dir)
    }

    func testEncodeDecodeRoundTripsRefresh() throws {
        let request = WidgetActionRequest(action: .refresh, pluginID: "cpu.5s.sh")
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(WidgetActionRequest.self, from: data)
        XCTAssertEqual(decoded, request)
        XCTAssertNil(decoded.actionIndex)
    }

    func testEncodeDecodeRoundTripsRunWithActionIndex() throws {
        let request = WidgetActionRequest(action: .run, pluginID: "deploy.15m.sh", actionIndex: 1)
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(WidgetActionRequest.self, from: data)
        XCTAssertEqual(decoded, request)
        XCTAssertEqual(decoded.actionIndex, 1)
    }

    func testWriteThenReadAndClearReturnsRequestOnce() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let request = WidgetActionRequest(action: .refresh, pluginID: "cpu.5s.sh")
        store.write(request)

        XCTAssertEqual(store.readAndClear(), request)
        // Consumed exactly once: a second read finds nothing.
        XCTAssertNil(store.readAndClear())
    }

    func testReadAndClearReturnsNilWhenAbsent() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(store.readAndClear())
    }

    func testWriteCreatesDirectoryIfNeeded() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        store.write(WidgetActionRequest(action: .refresh, pluginID: "a"))
        XCTAssertNotNil(store.readAndClear())
    }

    func testWriteRestrictsFileToOwnerOnly() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.write(WidgetActionRequest(action: .refresh, pluginID: "a"))
        let fileURL = dir.appendingPathComponent("widget-action-request.json")
        let mode = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? Int) ?? nil
        XCTAssertEqual(mode, 0o600)
    }

    func testOverwritingRequestReplacesThePending() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.write(WidgetActionRequest(action: .refresh, pluginID: "a"))
        store.write(WidgetActionRequest(action: .run, pluginID: "b", actionIndex: 0))

        XCTAssertEqual(store.readAndClear(), WidgetActionRequest(action: .run, pluginID: "b", actionIndex: 0))
    }
}
