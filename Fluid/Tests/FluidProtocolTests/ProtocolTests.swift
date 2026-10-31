import XCTest
@testable import FluidProtocol

final class LineCodecTests: XCTestCase {
    func testMessagesRoundTripAsSingleLines() throws {
        let row = RowNode(key: "pr-1", title: "Fix\nnewlines", subtitle: "repo", accessories: [.badge("Ready", role: .success)], actions: [ActionRef(id: "row/pr-1/Open", title: "Open", shortcut: "cmd+return")])
        let messages: [PluginMessage] = [
            .ready(protocolVersion: 1),
            .render(surface: .panel, root: .list(searchable: true, children: [.row(row), .divider])),
            .log(level: .warning, message: "careful"),
            .settled,
        ]
        for message in messages {
            let data = try LineCodec.encode(message)
            XCTAssertEqual(data.last, 0x0A)
            XCTAssertEqual(data.filter { $0 == 0x0A }.count, 1, "a message must be exactly one line")
            XCTAssertEqual(try LineCodec.decode(PluginMessage.self, from: data.dropLast()), message)
        }
        let host: [HostMessage] = [.hello(protocolVersion: 1, surfaces: [.menuBar]), .event(action: "toggle/x", value: .bool(true)), .trigger(reason: .wake), .shutdown]
        for message in host {
            XCTAssertEqual(try LineCodec.decode(HostMessage.self, from: try LineCodec.encode(message).dropLast()), message)
        }
    }

    func testManifestDefaultsAndInterval() throws {
        let manifest = Manifest(id: "a.b", name: "A", triggers: [.launch, .every(.seconds(30)), .minutes(1), .every(.milliseconds(10))])
        XCTAssertEqual(manifest.surfaces, [.menuBar, .panel])
        XCTAssertEqual(manifest.refreshInterval, 1, "sub-second intervals are raised to one second")
        let decoded = try LineCodec.decode(Manifest.self, from: try LineCodec.encode(manifest))
        XCTAssertEqual(decoded, manifest)
    }

    func testRowsAreFoundAnywhereInTheTree() {
        let tree = ViewNode.stack(axis: .vertical, children: [
            .text("hi"),
            .section(title: "A", children: [.row(RowNode(key: "1", title: "one"))]),
            .list(children: [.row(RowNode(key: "2", title: "two"))]),
        ])
        XCTAssertEqual(tree.rows.map(\.key), ["1", "2"])
    }
}

final class LineBufferTests: XCTestCase {
    func testJoinsPartialChunksAndSkipsEmptyLines() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(Data("ab".utf8)), [])
        XCTAssertEqual(buffer.append(Data("c\n\nde".utf8)), [Data("abc".utf8)])
        XCTAssertEqual(buffer.append(Data("f\ng\n".utf8)), [Data("def".utf8), Data("g".utf8)])
    }

    func testDropsOversizedLinesAndRecovers() {
        var buffer = LineBuffer(maxLineBytes: 4)
        XCTAssertEqual(buffer.append(Data("ok\n123".utf8)), [Data("ok".utf8)])
        XCTAssertEqual(buffer.append(Data("456789".utf8)), [], "a line past the cap is discarded, not buffered")
        XCTAssertEqual(buffer.append(Data("more\nnext\n".utf8)), [Data("next".utf8)])
        XCTAssertEqual(buffer.droppedLines, 1)
        XCTAssertEqual(buffer.append(Data("toolong\nfine\n".utf8)), [Data("fine".utf8)])
        XCTAssertEqual(buffer.droppedLines, 2)
    }
}
