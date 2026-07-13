import XCTest
import UserNotifications
import VeeCatalog
@testable import VeeApp

/// Covers the catalog "update available" nudge: coalesced notification text,
/// persisted de-dupe, and routing a tap to Discover. Deliberately never calls
/// `Notifier.post`/`.handle`/`UNUserNotificationCenter` directly (no app
/// bundle in the test process, and touching `NSApplication`/AppKit singletons
/// from a VeeApp unit test rebinds the MainActor executor process-wide and
/// starves other suites under CI load) — every piece here is exercised through
/// its pure, `UNUserNotificationCenter`-free surface instead.
final class NotificationUpdateTests: XCTestCase {
    // MARK: - Coalescing ("2 plugin updates available" style)

    func testBodySingularNamesThePlugin() {
        XCTAssertEqual(CatalogUpdateNudgeText.body(for: ["cpu.5s.sh"]), "cpu.5s.sh has an update available.")
    }

    func testBodyPluralCoalescesIntoOneLine() {
        XCTAssertEqual(
            CatalogUpdateNudgeText.body(for: ["weather.1m.py", "cpu.5s.sh"]),
            "2 plugin updates available: cpu.5s.sh, weather.1m.py."
        )
    }

    func testBodyEmptyIsEmptyString() {
        XCTAssertEqual(CatalogUpdateNudgeText.body(for: []), "")
    }

    func testBodyOrdersNamesDeterministically() {
        // Same set, different input order — the coalesced text must not
        // depend on scan/collection order.
        XCTAssertEqual(CatalogUpdateNudgeText.body(for: ["b.sh", "a.sh"]), CatalogUpdateNudgeText.body(for: ["a.sh", "b.sh"]))
    }

    // MARK: - De-dupe persistence (`UpdateNotificationStore`)

    private func ephemeralStore(_ suiteName: String) -> (UpdateNotificationStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (UpdateNotificationStore(defaults: defaults), defaults)
    }

    func testNeverNotifiedCandidateIsNotSeen() {
        let suite = "vee.updatenudge.\(UUID().uuidString)"
        let (store, defaults) = ephemeralStore(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(store.hasNotified(PluginUpdateCandidate(filename: "cpu.5s.sh", versionToken: "v1")))
    }

    func testMarkNotifiedPersistsTheExactPair() throws {
        let suite = "vee.updatenudge.\(UUID().uuidString)"
        let (store, defaults) = ephemeralStore(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let candidate = PluginUpdateCandidate(filename: "cpu.5s.sh", versionToken: "v1")

        store.markNotified([candidate])

        XCTAssertTrue(store.hasNotified(candidate))
        // Reloading from a fresh handle onto the same suite still sees it —
        // this is persisted, not in-memory only.
        XCTAssertTrue(UpdateNotificationStore(defaults: UserDefaults(suiteName: suite)!).hasNotified(candidate))
    }

    func testDifferentVersionForSamePluginIsNotConsideredNotified() throws {
        let suite = "vee.updatenudge.\(UUID().uuidString)"
        let (store, defaults) = ephemeralStore(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        store.markNotified([PluginUpdateCandidate(filename: "cpu.5s.sh", versionToken: "v1")])

        // A newer version than the one already surfaced is a new pair.
        XCTAssertFalse(store.hasNotified(PluginUpdateCandidate(filename: "cpu.5s.sh", versionToken: "v2")))
    }

    func testMarkNotifiedOverwritesPriorVersionForSamePlugin() throws {
        let suite = "vee.updatenudge.\(UUID().uuidString)"
        let (store, defaults) = ephemeralStore(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        store.markNotified([PluginUpdateCandidate(filename: "cpu.5s.sh", versionToken: "v1")])
        store.markNotified([PluginUpdateCandidate(filename: "cpu.5s.sh", versionToken: "v2")])

        XCTAssertFalse(store.hasNotified(PluginUpdateCandidate(filename: "cpu.5s.sh", versionToken: "v1")))
        XCTAssertTrue(store.hasNotified(PluginUpdateCandidate(filename: "cpu.5s.sh", versionToken: "v2")))
    }

    func testMultiplePluginsCoexistInTheLedger() throws {
        let suite = "vee.updatenudge.\(UUID().uuidString)"
        let (store, defaults) = ephemeralStore(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = PluginUpdateCandidate(filename: "a.sh", versionToken: "v1")
        let b = PluginUpdateCandidate(filename: "b.sh", versionToken: "v1")
        store.markNotified([a, b])

        XCTAssertTrue(store.hasNotified(a))
        XCTAssertTrue(store.hasNotified(b))
    }

    // MARK: - De-dupe filter (`Notifier.unnotifiedCandidates`)

    @MainActor
    func testUnnotifiedCandidatesFiltersOutAlreadySeenPairs() {
        let suite = "vee.updatenudge.\(UUID().uuidString)"
        let (store, defaults) = ephemeralStore(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let seen = PluginUpdateCandidate(filename: "cpu.5s.sh", versionToken: "v1")
        let unseen = PluginUpdateCandidate(filename: "weather.1m.py", versionToken: "v1")
        store.markNotified([seen])

        XCTAssertEqual(Notifier.unnotifiedCandidates([seen, unseen], store: store), [unseen])
    }

    @MainActor
    func testUnnotifiedCandidatesIncludesNewerVersionOfAlreadySeenPlugin() {
        let suite = "vee.updatenudge.\(UUID().uuidString)"
        let (store, defaults) = ephemeralStore(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        store.markNotified([PluginUpdateCandidate(filename: "cpu.5s.sh", versionToken: "v1")])
        let newer = PluginUpdateCandidate(filename: "cpu.5s.sh", versionToken: "v2")

        XCTAssertEqual(Notifier.unnotifiedCandidates([newer], store: store), [newer])
    }

    @MainActor
    func testUnnotifiedCandidatesEmptyWhenAllSeen() {
        let suite = "vee.updatenudge.\(UUID().uuidString)"
        let (store, defaults) = ephemeralStore(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let candidate = PluginUpdateCandidate(filename: "cpu.5s.sh", versionToken: "v1")
        store.markNotified([candidate])

        XCTAssertEqual(Notifier.unnotifiedCandidates([candidate], store: store), [])
    }

    // MARK: - Routing target (tapping the nudge opens Discover)

    func testDefaultTapOnUpdateNudgeOpensDiscover() {
        XCTAssertEqual(
            NotificationRouter.route(actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier", pluginID: nil, href: nil, isUpdateNudge: true),
            .openDiscover
        )
    }

    func testUpdateNudgeTakesPrecedenceOverHref() {
        // An update nudge never carries a plugin href, but even if one were
        // present, opening Discover is the correct behavior for this category.
        let url = URL(string: "https://example.com")!
        XCTAssertEqual(
            NotificationRouter.route(actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier", pluginID: nil, href: url, isUpdateNudge: true),
            .openDiscover
        )
    }

    func testDismissingUpdateNudgeDoesNotOpenDiscover() {
        XCTAssertEqual(
            NotificationRouter.route(actionIdentifier: UNNotificationDismissActionIdentifier, pluginID: nil, href: nil, isUpdateNudge: true),
            .none
        )
    }

    func testNonUpdateNotificationsUnaffectedByNewParameter() {
        // Regression: adding `isUpdateNudge` must not change routing when
        // it's left at its default (false) — existing plugin-alert behavior
        // is untouched.
        XCTAssertEqual(
            NotificationRouter.route(actionIdentifier: "RERUN", pluginID: "cpu.5s.sh", href: nil),
            .rerun(pluginID: "cpu.5s.sh")
        )
    }

    func testCategoryIdentifierIsStable() {
        XCTAssertEqual(NotificationRouter.updateCategoryID, "VEE_CATALOG_UPDATE")
    }
}
