import FluidKit
import Foundation

/// A test plugin that misbehaves on request: its buttons crash the process or
/// print to stdout, so the supervisor and the stdio guard are tested against a
/// real process.
@main
final class Fixture: FluidPlugin {
    static let manifest = Manifest(id: "dev.fluid.test.fixture", name: "Fixture", triggers: [.launch])

    var count = 0

    var menuBar: ViewContent {
        Text("count \(count)")
    }

    var panel: ViewContent {
        Button("Increment") { self.count += 1 }
        Button("Print") {
            // Must land on stderr, not in the protocol stream.
            print("stray output from plugin code")
            self.count += 10
        }
        Button("Crash") { exit(3) }
    }
}
