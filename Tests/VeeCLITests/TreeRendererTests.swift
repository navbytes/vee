import XCTest
import VeePluginFormat
@testable import VeeCLI

final class TreeRendererTests: XCTestCase {
    func testKnownOutputRendersExpectedTree() {
        var linkParams = LineParams()
        linkParams.href = URL(string: "https://example.com/procs")

        var refreshParams = LineParams()
        refreshParams.refresh = true

        let details = MenuItem(text: "Details", submenu: [
            .item(MenuItem(text: "Load: 1.20")),
            .item(MenuItem(text: "Cores: 8"))
        ])

        var titleParams = LineParams()
        titleParams.color = .named("green")
        titleParams.swiftbar.sfimage = "cpu"

        let output = ParsedOutput(
            titleLines: [TitleLine(text: "CPU 12%", params: titleParams)],
            body: [
                .item(MenuItem(text: "Top processes", params: linkParams)),
                .separator,
                .item(details),
                .item(MenuItem(text: "Refresh", params: refreshParams))
            ])

        let expected = """
        CPU 12%  [color=green sfimage=cpu]
        ---
        Top processes  [href=https://example.com/procs]
        ───
        Details
          Load: 1.20
          Cores: 8
        Refresh  [refresh]
        """

        XCTAssertEqual(TreeRenderer.render(output), expected)
    }

    func testSurfacesControlAndProgressParams() {
        var toggleP = LineParams(); toggleP.control = .toggle(on: true)
        var sliderP = LineParams(); sliderP.control = .slider(min: 0, max: 10, value: 3)
        var progP = LineParams(); progP.progress = ProgressParams(fraction: 0.72)

        let output = ParsedOutput(body: [
            .item(MenuItem(text: "Mute", params: toggleP)),
            .item(MenuItem(text: "Volume", params: sliderP)),
            .item(MenuItem(text: "Sync", params: progP))
        ])

        let rendered = TreeRenderer.render(output)
        XCTAssertTrue(rendered.contains("toggle=on"), rendered)
        XCTAssertTrue(rendered.contains("slider=0,10,3"), rendered)
        XCTAssertTrue(rendered.contains("progress=0.72"), rendered)
    }
}
