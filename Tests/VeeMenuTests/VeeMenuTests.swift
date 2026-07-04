import XCTest
import AppKit
import VeePluginFormat
@testable import VeeMenu

@MainActor
final class DummyHandler: MenuActionHandling {
    func perform(_ item: MenuItem) {}
}

@MainActor
final class ColorResolverTests: XCTestCase {
    func testNamed() {
        XCTAssertEqual(ColorResolver.nsColor(for: .named("red")), .systemRed)
        XCTAssertEqual(ColorResolver.nsColor(for: .named("labelcolor")), .labelColor)
        XCTAssertNil(ColorResolver.nsColor(for: .named("chartreuse")))
    }

    func testRGB() {
        let c = ColorResolver.nsColor(for: .rgb(r: 255, g: 0, b: 0, a: 255))
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.usingColorSpace(.sRGB)?.redComponent ?? 0, 1.0, accuracy: 0.01)
    }
}

@MainActor
final class AttributedTitleFactoryTests: XCTestCase {
    private let font = NSFont.menuFont(ofSize: 0)

    func testColorApplied() {
        var params = LineParams()
        params.color = .named("red")
        let s = AttributedTitleFactory.make(text: "hi", params: params, ansiRuns: [], defaultFont: font)
        let color = s.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, .systemRed)
    }

    func testLengthTruncation() {
        var params = LineParams()
        params.length = 3
        let s = AttributedTitleFactory.make(text: "abcdef", params: params, ansiRuns: [], defaultFont: font)
        XCTAssertEqual(s.string, "abc…")
    }

    func testAnsiRunColor() {
        let runs = [AnsiRun(range: 0..<1, foreground: .named("blue"))]
        let s = AttributedTitleFactory.make(text: "AB", params: LineParams(), ansiRuns: runs, defaultFont: font)
        let color = s.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, .systemBlue)
    }
}

@MainActor
final class MenuBuilderTests: XCTestCase {
    // NSMenuItem.target is weak, so the action target must be retained for the
    // lifetime of the assertions (the real app retains it in StatusItemController).
    private var retainedTargets: [MenuActionTarget] = []

    private func menu(_ source: String) -> NSMenu {
        let output = OutputParser.parse(source)
        let target = MenuActionTarget(handler: DummyHandler())
        retainedTargets.append(target)
        return MenuBuilder.build(output.body, target: target)
    }

    func testItemsAndSeparators() {
        let m = menu("T\n---\nAlpha\n---\nBeta")
        XCTAssertEqual(m.items.count, 3)
        XCTAssertEqual(m.items[0].title, "Alpha")
        XCTAssertTrue(m.items[1].isSeparatorItem)
        XCTAssertEqual(m.items[2].title, "Beta")
    }

    func testSubmenu() {
        let m = menu("T\n---\nParent\n--Child")
        XCTAssertEqual(m.items[0].title, "Parent")
        XCTAssertNotNil(m.items[0].submenu)
        XCTAssertEqual(m.items[0].submenu?.items.first?.title, "Child")
    }

    func testActionableItemGetsTarget() {
        let m = menu("T\n---\nClickable | href=https://example.com\nInert")
        XCTAssertNotNil(m.items[0].target, "href item should be wired")
        XCTAssertNil(m.items[1].target, "plain item should be inert")
    }

    func testCheckedAndDisabled() {
        let m = menu("T\n---\nOn | checked=true\nOff | disabled=true")
        XCTAssertEqual(m.items[0].state, .on)
        XCTAssertFalse(m.items[1].isEnabled)
    }

    func testAlternateItemFlagged() {
        let m = menu("T\n---\nOpen\nOpen in background | alternate=true")
        XCTAssertEqual(m.items.count, 2)
        XCTAssertFalse(m.items[0].isAlternate)
        XCTAssertTrue(m.items[1].isAlternate)
        XCTAssertEqual(m.items[1].keyEquivalentModifierMask, .option)
    }
}
