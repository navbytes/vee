# Fluid

Fluid is a native macOS host for small, live apps that you (or an AI) write in
Swift. A plugin is one `.swift` file. It declares what it shows in a
SwiftUI-like syntax, and Fluid builds it, runs it in its own process, and draws
it natively in the menu bar and in a panel. It is the successor to Vee for
developers who want apps rather than scripts. Vee keeps serving script and
xbar plugins.

The vision and architecture are in the design doc
([Fluid: the successor to Vee](https://claude.ai/artifact/FKTDdAHT9q76TojhZkS2K9)).
This package is **Phase 0**: the smallest end-to-end slice that proves the
model.

## A plugin

```swift
import FluidKit
import Foundation

@main
final class Clock: FluidPlugin {
    static let manifest = Manifest(
        id: "dev.example.clock",
        name: "Clock",
        triggers: [.launch, .every(.seconds(1))]
    )

    var now = Date()
    var laps: [Date] = []

    func refresh() async throws { now = Date() }

    var menuBar: ViewContent {
        Label(now.formatted(date: .omitted, time: .standard), symbol: "clock")
    }

    var panel: ViewContent {
        Text(now.formatted(date: .complete, time: .omitted)).style(.headline)
        Button("Lap", symbol: "flag") { self.laps.insert(Date(), at: 0) }
        List(laps, searchable: true) { lap in
            Row(lap.formatted(date: .omitted, time: .standard), key: "\(lap.timeIntervalSince1970)")
        }
    }
}
```

State is ordinary properties. `refresh()` runs when a trigger fires. Action
closures run when the user clicks. After each, Fluid re-renders and sends only
the surfaces that changed. Messages are handled one at a time, so plugin code
never runs concurrently with itself and needs no locks.

**The vocabulary** (`Sources/FluidKit/Views.swift`): `Text`, `Label`,
`VStack`, `HStack`, `List`, `Section`, `ForEach`, `Row` (with `.badge`,
`.progress` and `.action`), `Badge`, `Button`, `Toggle`, `ProgressBar` and
`Divider`. Colors come from a `Role` (`.primary`, `.secondary`, `.accent`,
`.success`, `.warning`, `.critical`), never from values you pick, so every
plugin looks native in light and dark mode.

**The manifest** declares surfaces, triggers (`.launch`, `.every(...)`,
`.minutes(...)`, `.wake`) and capabilities (`.network(...)`, `.files(...)`,
`.run(...)`, `.secret(...)`). Capabilities become the App Sandbox
entitlements the helper is signed with (see "What is not verified yet").

## Running it

On a Mac with Xcode 26:

```sh
cd Fluid
swift run Fluid                                   # menu-bar app; offers to install the examples
swift run Fluid --plugin Examples/ClockPlugin/Clock.swift
```

Plugins live in `~/Library/Application Support/Fluid/Plugins/*.swift`. The
first build of each plugin also compiles FluidKit, which takes a few seconds.
After that the build is cached by content. The PR Cockpit example reads
`GITHUB_TOKEN` from the environment.

### fluidctl: the headless authoring loop

`fluidctl` builds and drives a plugin without the app, on macOS or Linux. It is
what an agent uses to write a plugin: build it, read the compiler errors,
render it, press its buttons, and render it again.

```sh
swift run fluidctl build Examples/ClockPlugin/Clock.swift        # prints the helper path or compiler errors
swift run fluidctl manifest Examples/PRCockpitPlugin/PRCockpit.swift
swift run fluidctl render Examples/ClockPlugin/Clock.swift --surface panel \
    --event "toggle/24-hour clock" --event button/Lap
```

`render` prints each surface as text, with the action id next to every
control, so you can pass those ids to `--event`. Add `--json` for the raw tree
or `--verbose` for the plugin's log.

## How it fits together

| Module | What it does |
| --- | --- |
| `FluidProtocol` | The wire contract: `ViewNode`, `Manifest`, and the host and plugin messages (newline-delimited JSON). Depends on nothing. |
| `FluidKit` | What plugins import: the DSL, `FluidPlugin`, and the runtime loop. It redirects the plugin's own stdout to stderr, so a stray `print` can't corrupt the protocol. |
| `FluidHostCore` | The host's core with no UI: `PluginBuilder` (a single file to a cached helper, with compiler diagnostics mapped back to the file), `PluginProcess` (pipes, bounded line reads), `PluginSupervisor` (hello, triggers, events, restart with backoff), `SandboxEntitlements` and `TreeTextRenderer`. |
| `Fluid` | The AppKit/SwiftUI app: one status item per plugin, with a popover panel that renders the tree. |
| `fluidctl` | The CLI described above. |

Each plugin runs as a separate helper process, never inside the app. A crash
or a leak in one plugin can't take the host down, and the supervisor keeps the
last tree on screen while it restarts the helper.

## Tests

```sh
swift build && swift test                      # protocol, DSL, runtime, and supervisor against real helper processes
FLUID_BUILD_TESTS=1 swift test                 # also compiles plugins through PluginBuilder (slow)
```

Everything except the `Fluid` app target builds and is tested on Linux as
well. The `Fluid` CI workflow compiles the app on macOS.

## What is not verified yet

Phase 0 was written and tested on Linux, so nothing on a Mac has been checked
yet. These are the checks for a real Mac, in order:

1. **The app.** Run `swift build` and `swift run Fluid`. Check that the Clock
   example ticks in the menu bar, and that its panel's toggle, Lap button,
   filter field and row clicks work.
2. **The sandbox.** Run with `FLUID_SANDBOX=1`. Check that the helper is signed
   ad hoc with entitlements generated from its manifest
   (`codesign -d --entitlements - <helper>`), and that a plugin without
   `.network` can't reach the network. Neither has been verified yet.
3. **ExtensionKit.** Not built yet. Check that a locally built extension can be
   discovered and embedded, before the panel escape hatch depends on it.
4. **The gate.** Run PR Cockpit for a week and check that the helper's and the
   host's memory stay flat.

## Phase 0 shortcuts

These are marked `ponytail:` in the code:

- Helpers are launched with Foundation's `Process`, so timeouts don't reap the
  process group. Vee's `posix_spawn` runner moves into a shared package in
  phase 1.
- Every plugin compiles its own copy of FluidKit.
- The app finds FluidKit next to its own source, which suits development
  builds. A distributed app will bundle it.
- There is no host storage, OAuth broker or HTTP service yet, so plugins use
  `URLSession` and environment variables directly.
