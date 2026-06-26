import XCTest
@testable import VeeEngine

/// R2-CRIT-1 regression (docs/AUDIT-2.md): the production `DispatchClock` fires a
/// one-shot timer's handler *on its own serial queue*, and the handler then calls
/// `cancel(token)`. Before the re-entrancy guard, that `cancel` did `queue.sync`
/// onto the already-held queue — a same-queue deadlock/trap. The existing suite
/// missed it because it injects a `TestClock` that fires inline; these tests use
/// the REAL `DispatchClock` and let a one-shot actually elapse.
final class DispatchClockTests: XCTestCase {

    func testOneShotTimerFiresAndSelfCancelsWithoutDeadlock() {
        let clock = DispatchClock()
        let fired = expectation(description: "one-shot handler ran")
        _ = clock.schedule(after: 0.01, repeats: false) { fired.fulfill() }
        // Before the fix this hangs (deadlock) or traps inside the handler's
        // self-`cancel`; after it, the handler completes normally.
        wait(for: [fired], timeout: 2.0)
    }

    func testRepeatingTimerFiresAndExternalCancelStops() {
        let clock = DispatchClock()
        let fired = expectation(description: "repeating handler ran")
        fired.assertForOverFulfill = false
        let token = clock.schedule(after: 0.01, repeats: true) { fired.fulfill() }
        wait(for: [fired], timeout: 2.0)
        clock.cancel(token)   // external (off-queue) cancel must also not deadlock
    }

    func testManyOneShotsAllFire() {
        let clock = DispatchClock()
        let all = expectation(description: "all one-shots ran")
        all.expectedFulfillmentCount = 20
        for _ in 0..<20 { _ = clock.schedule(after: 0.01, repeats: false) { all.fulfill() } }
        wait(for: [all], timeout: 3.0)
    }
}
