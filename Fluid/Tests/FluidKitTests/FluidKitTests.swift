import Foundation
import XCTest
@testable import FluidKit

/// Collects what a runtime sends, from any thread.
final class Outbox: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [PluginMessage] = []

    var send: PluginRuntime.Send { { message in self.lock.withLock { self.messages.append(message) } } }

    func take() -> [PluginMessage] {
        lock.withLock {
            defer { messages.removeAll() }
            return messages
        }
    }
}

struct Boom: Error {}

@MainActor
final class Counter: FluidPlugin {
    static let manifest = Manifest(id: "test.counter", name: "Counter", surfaces: [.menuBar, .panel])

    var count = 0
    var refreshes = 0
    var shouldFail = false
    var enabled = false
    var items = ["a", "b"]

    func refresh() async throws {
        if shouldFail { throw Boom() }
        refreshes += 1
    }

    var menuBar: ViewContent {
        Label("\(count)", symbol: "number")
    }

    var panel: ViewContent {
        Text("Count").style(.headline)
        Button("Add") { self.count += 1 }
        Toggle("Enabled", isOn: enabled) { self.enabled = $0 }
        if count > 2 {
            Text("big").role(.warning)
        }
        List(items) { item in
            Row(item, key: "item-\(item)").badge("new").action("Remove") { self.items.removeAll { $0 == item } }
        }
    }
}

@MainActor
final class FluidKitTests: XCTestCase {
    func testDSLResolvesToTheExpectedTree() {
        let plugin = Counter()
        let context = RenderContext()
        let nodes = plugin.panel.resolve(in: context)
        XCTAssertEqual(nodes.count, 4)
        XCTAssertEqual(nodes[0], .text("Count", style: .headline, role: .primary))
        XCTAssertEqual(nodes[1], .button(title: "Add", symbol: nil, role: .primary, action: "button/Add"))
        XCTAssertEqual(nodes[2], .toggle(title: "Enabled", isOn: false, action: "toggle/Enabled"))
        guard case .list(false, let rows) = nodes[3] else { return XCTFail("expected a list") }
        XCTAssertEqual(rows, [
            .row(RowNode(key: "item-a", title: "a", accessories: [.badge("new", role: .secondary)], actions: [ActionRef(id: "row/item-a/Remove", title: "Remove")])),
            .row(RowNode(key: "item-b", title: "b", accessories: [.badge("new", role: .secondary)], actions: [ActionRef(id: "row/item-b/Remove", title: "Remove")])),
        ])
        XCTAssertEqual(Set(context.handlers.keys), ["button/Add", "toggle/Enabled", "row/item-a/Remove", "row/item-b/Remove"])
    }

    func testDuplicateActionNamesGetSuffixesInsteadOfReplacingHandlers() {
        let context = RenderContext()
        let first = context.register("button/Go") { _ in }
        let second = context.register("button/Go") { _ in }
        XCTAssertEqual(first, "button/Go")
        XCTAssertEqual(second, "button/Go#2")
    }

    func testHelloAnswersReadyThenRendersOnlyOfferedSurfaces() async {
        let outbox = Outbox()
        let runtime = PluginRuntime(plugin: Counter(), send: outbox.send)
        await runtime.handle(.hello(protocolVersion: 1, surfaces: [.menuBar]))
        XCTAssertEqual(outbox.take(), [
            .ready(protocolVersion: FluidProtocolVersion.current),
            .render(surface: .menuBar, root: .label("0", symbol: "number", role: .primary)),
            .settled,
        ])
    }

    func testEventsRunHandlersAndOnlyChangedSurfacesAreResent() async throws {
        let outbox = Outbox()
        let plugin = Counter()
        let runtime = PluginRuntime(plugin: plugin, send: outbox.send)
        await runtime.handle(.hello(protocolVersion: 1, surfaces: [.menuBar, .panel]))
        _ = outbox.take()

        await runtime.handle(.trigger(reason: .interval))
        XCTAssertEqual(plugin.refreshes, 1)
        XCTAssertEqual(outbox.take(), [.settled], "an unchanged render is not sent again")

        await runtime.handle(.event(action: "button/Add", value: nil))
        XCTAssertEqual(plugin.count, 1)
        let sent = outbox.take()
        XCTAssertEqual(sent.count, 2, "the panel did not change, so only the menu bar is resent")
        XCTAssertEqual(sent.first, .render(surface: .menuBar, root: .label("1", symbol: "number", role: .primary)))

        await runtime.handle(.event(action: "toggle/Enabled", value: .bool(true)))
        XCTAssertTrue(plugin.enabled)
        await runtime.handle(.event(action: "row/item-a/Remove", value: nil))
        XCTAssertEqual(plugin.items, ["b"])
    }

    func testFailuresAreLoggedNotFatal() async {
        let outbox = Outbox()
        let plugin = Counter()
        let runtime = PluginRuntime(plugin: plugin, send: outbox.send)
        await runtime.handle(.hello(protocolVersion: 1, surfaces: [.menuBar]))
        _ = outbox.take()

        plugin.shouldFail = true
        let afterTrigger = await runtime.handle(.trigger(reason: .manual))
        XCTAssertTrue(afterTrigger)
        guard case .log(.error, let message) = outbox.take().first else { return XCTFail("expected an error log") }
        XCTAssertTrue(message.contains("refresh failed"))

        let afterEvent = await runtime.handle(.event(action: "button/Missing", value: nil))
        XCTAssertTrue(afterEvent)
        XCTAssertEqual(outbox.take(), [.log(level: .warning, message: "no handler for action button/Missing"), .settled])
    }

    func testVisibilityResendsTheSurfaceAndShutdownStops() async {
        let outbox = Outbox()
        let runtime = PluginRuntime(plugin: Counter(), send: outbox.send)
        await runtime.handle(.hello(protocolVersion: 1, surfaces: [.menuBar]))
        _ = outbox.take()
        await runtime.handle(.visibility(surface: .menuBar, visible: true))
        XCTAssertEqual(outbox.take().count, 2)
        let keepGoing = await runtime.handle(.shutdown)
        XCTAssertFalse(keepGoing)
    }
}
