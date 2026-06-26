import XCTest
@testable import VeeApp
import VeeProtocol
import VeeEngine

/// R2-MED-3 regression: when `JSONPatch.apply` failed, `applyRender` used to
/// return WITHOUT advancing the mirror, but the host had already advanced its
/// revision — so every later diff mis-applied onto the stale base and the surface
/// froze permanently. The fix RESETS the mirror (mirror=nil, lastRevision=0, drop
/// to a refreshing state) on apply failure, so the host's next full render (a
/// `replace ""` keyframe) re-syncs cleanly. These tests prove the surface recovers
/// rather than freezing.
final class MirrorResyncTests: XCTestCase {

    private func renderNote(pluginId: String, revision: Int,
                            patch: JSONPatchDocument) throws -> JSONRPCMessage {
        let params = RenderParams(pluginId: pluginId, revision: revision, patch: patch)
        let value = try JSONDecoder().decode(JSONValue.self, from: try JSONEncoder().encode(params))
        return .notification(JSONRPCNotification(method: RPCMethods.render, params: value))
    }

    private func listTree(_ titles: [(id: String, title: String)]) -> RenderNode {
        RenderNode(tag: RenderNode.Tag.root, children: [
            RenderNode(tag: RenderNode.Tag.list, children: titles.map {
                RenderNode(tag: RenderNode.Tag.listItem, key: $0.id,
                           props: ["title": .string($0.title)])
            })
        ])
    }

    /// The headline scenario: valid render → bad patch (apply fails) → full replace
    /// keyframe → the surface shows the NEW tree, not the frozen old one.
    func testSurfaceRecoversAfterFailedPatchThenKeyframe() throws {
        let transport = TestPeerTransport()
        let coordinator = AppCoordinator(pluginId: "com.vee.test", transport: transport, host: FakeHost())
        coordinator.activatePlugin("com.vee.test", command: "view")

        // 1. A valid first render establishes the mirror at revision 1.
        transport.deliverInbound(try renderNote(
            pluginId: "com.vee.test", revision: 1,
            patch: [.replace("", listTree([(id: "a", title: "Alpha")]).jsonValue)]))
        XCTAssertEqual(coordinator.listViewModel?.items.map(\.title), ["Alpha"])

        // 2. A bad patch the host emits at revision 2: it targets a pointer that
        // doesn't exist in our mirror, so JSONPatch.apply throws → desync.
        transport.deliverInbound(try renderNote(
            pluginId: "com.vee.test", revision: 2,
            patch: [.replace("/children/9/props/title", .string("nope"))]))

        // The fix drops to a refreshing state (not the frozen old list).
        XCTAssertNil(coordinator.listViewModel,
                     "after a failed patch the desynced list must be dropped, not frozen")
        XCTAssertEqual(coordinator.emptyViewModel?.title, "Refreshing…",
                       "a desync should drop to a neutral refreshing surface")

        // 3. The host re-renders the whole tree as a keyframe. Critically this
        // arrives at revision 3 (> the host's advanced revision) AND, because the
        // mirror reset lastRevision to 0, it is NOT dropped as stale.
        transport.deliverInbound(try renderNote(
            pluginId: "com.vee.test", revision: 3,
            patch: [.replace("", listTree([(id: "b", title: "Bravo"),
                                           (id: "c", title: "Charlie")]).jsonValue)]))

        XCTAssertEqual(coordinator.listViewModel?.items.map(\.title), ["Bravo", "Charlie"],
                       "the keyframe after a desync must re-sync the surface (not stay frozen)")
        XCTAssertEqual(coordinator.selectedID, "b")
    }

    /// Without the reset, a later VALID diff would mis-apply onto the poisoned
    /// mirror. After the reset, a plain incremental diff (no keyframe) can't apply
    /// to the empty mirror and is itself dropped+reset — but the surface still
    /// recovers on the next keyframe rather than ever applying onto stale state.
    func testIncrementalDiffAfterDesyncDoesNotResurrectStaleTree() throws {
        let transport = TestPeerTransport()
        let coordinator = AppCoordinator(pluginId: "com.vee.test", transport: transport, host: FakeHost())
        coordinator.activatePlugin("com.vee.test", command: "view")

        transport.deliverInbound(try renderNote(
            pluginId: "com.vee.test", revision: 1,
            patch: [.replace("", listTree([(id: "a", title: "Alpha")]).jsonValue)]))

        // Desync via a bad patch.
        transport.deliverInbound(try renderNote(
            pluginId: "com.vee.test", revision: 2,
            patch: [.remove("/children/0/children/5")]))
        XCTAssertNil(coordinator.listViewModel)

        // A subsequent incremental prop diff (revision 3) can't apply to the now
        // -empty mirror; it's dropped, and the surface still does not show "Alpha".
        transport.deliverInbound(try renderNote(
            pluginId: "com.vee.test", revision: 3,
            patch: [.replace("/children/0/children/0/props/title", .string("Mutated"))]))
        XCTAssertNil(coordinator.listViewModel?.items.first?.title)

        // The eventual keyframe re-syncs cleanly.
        transport.deliverInbound(try renderNote(
            pluginId: "com.vee.test", revision: 4,
            patch: [.replace("", listTree([(id: "z", title: "Zeta")]).jsonValue)]))
        XCTAssertEqual(coordinator.listViewModel?.items.map(\.title), ["Zeta"])
    }

    /// A normal valid incremental diff (no failure) must keep working unchanged —
    /// the reset only triggers on apply failure, never on the happy path.
    func testValidIncrementalDiffStillAppliesNormally() throws {
        let transport = TestPeerTransport()
        let coordinator = AppCoordinator(pluginId: "com.vee.test", transport: transport, host: FakeHost())
        coordinator.activatePlugin("com.vee.test", command: "view")

        transport.deliverInbound(try renderNote(
            pluginId: "com.vee.test", revision: 1,
            patch: [.replace("", listTree([(id: "a", title: "Alpha")]).jsonValue)]))
        // A well-formed prop replace against the real mirror applies fine.
        transport.deliverInbound(try renderNote(
            pluginId: "com.vee.test", revision: 2,
            patch: [.replace("/children/0/children/0/props/title", .string("Alpha v2"))]))
        XCTAssertEqual(coordinator.listViewModel?.items.map(\.title), ["Alpha v2"])
    }
}
