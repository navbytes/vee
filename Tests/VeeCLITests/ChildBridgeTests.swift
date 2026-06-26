import XCTest
@testable import vee
import VeeApp
import VeeEngine
import VeeProtocol

/// R2-CRIT-2 integration: prove the out-of-process plugin path the app now uses
/// actually works end-to-end — a real `vee-plugin-host` child, driven through the
/// `ChildCoordinatorTransport` + `ChildActivatingHost` adapters by a real
/// `AppCoordinator`, renders the essentials fixture's list into the coordinator's
/// surface. This is the launcher's production wiring minus AppKit. Skipped (not
/// failed) when the child binary isn't built.
final class ChildBridgeTests: XCTestCase {

    private func locatePluginHost() throws -> URL {
        let fm = FileManager.default
        if let explicit = ProcessInfo.processInfo.environment["VEE_PLUGIN_HOST"],
           fm.isExecutableFile(atPath: explicit) { return URL(fileURLWithPath: explicit) }
        // The xctest bundle lives in the build products dir; the child is a sibling
        // (or one level up for some layouts).
        let bundleDir = Bundle(for: type(of: self)).bundleURL.deletingLastPathComponent()
        for dir in [bundleDir, bundleDir.deletingLastPathComponent()] {
            let url = dir.appendingPathComponent("vee-plugin-host")
            if fm.isExecutableFile(atPath: url.path) { return url }
        }
        throw XCTSkip("vee-plugin-host not built; set VEE_PLUGIN_HOST or `swift build`")
    }

    /// Records the coordinator's projected list as it reaches the window seam.
    private final class RenderSpy: LauncherWindowPresenting {
        var onList: (([String]) -> Void)?
        func setRootViewModel(_ root: RootViewModel?) {
            if case .list(let list)? = root { onList?(list.items.map(\.title)) }
        }
        func showLauncher() {}
        func hideLauncher() {}
    }

    @MainActor
    func testEssentialsRendersThroughChildBridgeIntoCoordinator() throws {
        let exe = try locatePluginHost()
        let child = ChildProcessHost(executableURL: exe, requestTimeout: 15)
        try child.start()
        defer { child.terminate() }

        let coordinator = AppCoordinator(
            pluginId: "com.vee.launcher",
            transport: ChildCoordinatorTransport(child),
            host: ChildActivatingHost(child))
        let spy = RenderSpy()
        coordinator.window = spy

        let rendered = expectation(description: "essentials list reached the coordinator via the child bridge")
        rendered.assertForOverFulfill = false
        spy.onList = { titles in if titles.contains("Search Files") { rendered.fulfill() } }

        let source = try String(
            contentsOfFile: FileManager.default.currentDirectoryPath
                + "/plugins/fixtures/com.vee.essentials.bundle.js",
            encoding: .utf8)
        let manifest = PluginManifest(
            id: "com.vee.essentials", name: "Essentials", version: "1.0.0", entrypoint: "x",
            commands: [PluginCommand(name: "view", title: "View", mode: .view)],
            capabilities: Capabilities())
        try child.load(manifest: manifest, source: source)
        coordinator.activatePlugin("com.vee.essentials", command: "view")

        wait(for: [rendered], timeout: 20)
        XCTAssertEqual(coordinator.pluginId, "com.vee.essentials")
        XCTAssertTrue((coordinator.listViewModel?.items.map(\.title) ?? []).contains("Search Files"))
    }
}
