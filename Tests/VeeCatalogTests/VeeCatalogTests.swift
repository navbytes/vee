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

final class CommitDateParserTests: XCTestCase {
    private let commitsJSON = """
    [
      {"sha":"abc","commit":{"committer":{"name":"Bob","date":"2021-03-14T09:30:00Z"}}},
      {"sha":"def","commit":{"committer":{"name":"Al","date":"2019-01-01T00:00:00Z"}}}
    ]
    """

    func testParsesFirstCommitterDate() throws {
        let date = try XCTUnwrap(CatalogParser.parseLastCommitDate(commitsJSON: Data(commitsJSON.utf8)))
        XCTAssertEqual(date, ISO8601DateFormatter().date(from: "2021-03-14T09:30:00Z"))
    }

    func testEmptyArrayReturnsNil() {
        XCTAssertNil(CatalogParser.parseLastCommitDate(commitsJSON: Data("[]".utf8)))
    }

    func testMalformedJSONReturnsNil() {
        XCTAssertNil(CatalogParser.parseLastCommitDate(commitsJSON: Data("nope".utf8)))
    }
}

final class PluginFreshnessTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-07-06T00:00:00Z")!

    private func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 24 * 60 * 60)
    }

    func testNilLastUpdatedIsUnclassified() {
        XCTAssertNil(PluginFreshness.classify(lastUpdated: nil, now: now))
    }

    func testFreshUnderSixMonths() {
        XCTAssertEqual(PluginFreshness.classify(lastUpdated: daysAgo(30), now: now), .fresh)
        // Just under the 6-month boundary (~182.5 days).
        XCTAssertEqual(PluginFreshness.classify(lastUpdated: daysAgo(180), now: now), .fresh)
    }

    func testAgingBetweenSixMonthsAndTwoYears() {
        XCTAssertEqual(PluginFreshness.classify(lastUpdated: daysAgo(200), now: now), .aging)
        // Just under the 2-year boundary (~730 days).
        XCTAssertEqual(PluginFreshness.classify(lastUpdated: daysAgo(720), now: now), .aging)
    }

    func testStaleOverTwoYears() {
        XCTAssertEqual(PluginFreshness.classify(lastUpdated: daysAgo(1000), now: now), .stale)
    }
}

/// A fake catalog fetcher for exercising UI-adjacent logic without the network.
struct FakeCatalogFetcher: CatalogFetching {
    var index: [CatalogEntry] = []
    var source: String = ""
    var lastUpdated: Date?

    func fetchIndex() async throws -> [CatalogEntry] { index }
    func fetchSource(_ entry: CatalogEntry) async throws -> String { source }
    func fetchLastUpdated(_ entry: CatalogEntry) async throws -> Date? { lastUpdated }
}

final class FakeCatalogFetcherTests: XCTestCase {
    func testFakeReturnsInjectedLastUpdated() async throws {
        let date = ISO8601DateFormatter().date(from: "2022-05-01T00:00:00Z")!
        let fetcher = FakeCatalogFetcher(lastUpdated: date)
        let entry = CatalogEntry(path: "System/CPU/cpu.5s.sh", category: "System", filename: "cpu.5s.sh", rawURL: URL(string: "https://example.com")!)
        let fetched = try await fetcher.fetchLastUpdated(entry)
        XCTAssertEqual(fetched, date)
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
