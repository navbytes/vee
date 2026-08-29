import XCTest
@testable import VeePluginFormat

/// The drift guard for `docs/design/surface-parity.md`. The ledger's
/// dispositions table is *generated* from `WidgetParity`, so a reason edited in
/// the switch and not in the document — or a row added to the document by hand
/// — fails here, with the replacement text in the failure message. Same
/// fixture-drift pattern the retired plugin SDKs used for their own golden
/// fixtures: compare against what is committed, and say how to make it
/// current.
///
/// The compiler already forces a new `MenuAccessory` case to be *answered*
/// (`WidgetParity.disposition(of:)` carries no `default`). This forces the
/// answer to be *published*.
final class WidgetParityTests: XCTestCase {
    private static let beginMarker = "<!-- BEGIN GENERATED: dispositions (WidgetParity) -->"
    private static let endMarker = "<!-- END GENERATED -->"

    /// One sample per `MenuAccessory` case, beside the menu spelling it is drawn
    /// from. Sampled rather than enumerated because the enum carries payloads
    /// and so cannot be `CaseIterable`; a new case fails `disposition(of:)`'s
    /// exhaustive switch first, and listing it here is the second half of that
    /// same answer.
    private static let accessories: [(menu: String, accessory: MenuAccessory)] = [
        ("`progress=`", .progress(ProgressParams(fraction: 0.5), tint: nil)),
        ("`sparkline=`", .sparkline([1, 2, 3], style: SparklineStyle(), tint: nil)),
        ("`pie=` / `donut=` / `stackedbar=`", .chart(ChartParams(kind: .pie, values: [1])))
    ]

    func testLedgerTableIsCurrent() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/design/surface-parity.md")
        let document = try String(contentsOf: url, encoding: .utf8)

        guard let begin = document.range(of: Self.beginMarker),
              let end = document.range(of: Self.endMarker) else {
            return XCTFail("docs/design/surface-parity.md has lost its generated-table markers")
        }

        let expected = "\(Self.beginMarker)\n\n\(dispositionsTable())\n\n\(Self.endMarker)"
        let committed = String(document[begin.lowerBound..<end.upperBound])
        XCTAssertEqual(committed, expected, """
            docs/design/surface-parity.md's dispositions table has drifted from \
            WidgetParity. Replace the marked section with:

            \(expected)
            """)
    }

    /// The ledger's generated section, as Markdown.
    private func dispositionsTable() -> String {
        var lines = ["### Display graphics (`MenuAccessory`)", "", "| Menu | Widget | Reason |", "|---|---|---|"]
        lines += Self.accessories.map { row($0.menu, WidgetParity.disposition(of: $0.accessory)) }
        lines += ["", "### Dispatchable actions (`MenuTree.dispatches`)", "", "| Menu | Widget | Reason |", "|---|---|---|"]
        lines += WidgetParity.ActionKind.allCases.map { row(spelling(of: $0), WidgetParity.disposition(ofActionKind: $0)) }
        return lines.joined(separator: "\n")
    }

    private func row(_ menu: String, _ disposition: WidgetParity.Disposition) -> String {
        switch disposition {
        case .supported:
            return "| \(menu) | supported | — |"
        case .excluded(let reason):
            // "Excluded with a stated reason" is the guarantee; an empty one
            // would publish a blank cell and answer nothing.
            XCTAssertFalse(reason.isEmpty, "\(menu) is excluded with no stated reason")
            return "| \(menu) | excluded | \(reason) |"
        }
    }

    /// How a plugin declares each action kind. Exhaustive, like the dispositions
    /// themselves — a new kind must be given a spelling before this compiles.
    private func spelling(of kind: WidgetParity.ActionKind) -> String {
        switch kind {
        case .control: return "`toggle=` / `slider=`"
        case .shell: return "`shell=` / `bash=`"
        case .webview: return "`webview=`"
        case .sparkline: return "`sparkline=` (click)"
        case .chart: return "`pie=` / `donut=` / `stackedbar=` (click)"
        case .href: return "`href=`"
        case .shortcut: return "`shortcut=`"
        case .refresh: return "`refresh=true`"
        }
    }
}
