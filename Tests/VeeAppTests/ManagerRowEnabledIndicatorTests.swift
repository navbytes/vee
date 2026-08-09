import XCTest
@testable import VeeApp
import VeePreferences
import VeeUI

/// `enabledPlugins()` runs a non-executable plugin bash-wrapped (matching
/// SwiftBar) — it isn't filtered by the execute bit. But the Plugin Manager
/// row used to show `isEnabled: isExecutable && !isDisabled` (IM10), so a
/// non-+x plugin displayed as permanently OFF and its toggle looked broken
/// (flipping it on would recompute the same row and snap right back to
/// off). The row must reflect `!isDisabled` alone.
///
/// Drives this through `makeLibraryModel` — the existing test seam
/// (`AppControllerDiscoverRoutingTests` already uses it the same way) that
/// never touches `NSApp`, unlike `openManager()`/`LibraryWindow`.
@MainActor
final class ManagerRowEnabledIndicatorTests: XCTestCase {
    private func tempDir() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vee-manager-row-\(UUID().uuidString)", isDirectory: true).path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Polls (deadline-bounded, not a fixed sleep) until `manager.isLoaded`
    /// flips — `makeLibraryModel` builds rows off the main thread via
    /// `Task.detached`.
    private func waitForLoad(_ manager: PluginManagerModel) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !manager.isLoaded, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(manager.isLoaded, "the manager model never finished loading rows")
    }

    func testNonExecutablePluginRowIsEnabledWhenNotDisabledAndToggleStillWorks() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        setenv("VEE_PLUGINS_DIR", dir, 1)
        defer { unsetenv("VEE_PLUGINS_DIR") }

        let filename = "nonexec-\(UUID().uuidString).sh"
        let path = (dir as NSString).appendingPathComponent(filename)
        // Deliberately no +x bit — the exact case `PluginDiscovery.enabled`
        // still loads (bash-wrapped) and this fix is about.
        try "#!/bin/bash\n# <vee.surface>widget</vee.surface>\necho hi\n".write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertFalse(FileManager.default.isExecutableFile(atPath: path), "sanity: no execute bit")

        let controller = AppController(secretStoreFactory: { _ in InMemorySecretStore() })
        defer { controller.applicationWillTerminate(Notification(name: Notification.Name("test-cleanup"))) }

        let manager = controller.makeLibraryModel(section: .installed).manager
        try await waitForLoad(manager)

        let row = try XCTUnwrap(manager.rows.first { $0.id == filename })
        XCTAssertTrue(row.isEnabled, "a non-executable plugin still runs (bash-wrapped) — the Manager row must reflect that, not the execute bit")

        manager.onToggleEnabled(filename, false)
        XCTAssertTrue(AppPreferences.shared.isDisabled(filename), "the toggle must still actually disable a non-+x plugin")
        AppPreferences.shared.setDisabled(false, id: filename) // tidy up real UserDefaults.standard state
    }
}
