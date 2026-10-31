import Foundation
import FluidHostCore
import FluidProtocol

// fluidctl — build, inspect and drive a Fluid plugin without the app.
//
// It is the headless half of the authoring loop: an agent (or a person in a
// terminal) can build a plugin, read the compiler's errors, render what each
// surface shows, press its buttons by action id, and read the result again.

let usage = """
usage:
  fluidctl build <plugin.swift>
  fluidctl manifest <plugin.swift | helper>
  fluidctl render <plugin.swift | helper> [--surface menuBar|panel] [--event <action-id>]... [--json] [--verbose]

A .swift path is built first (cached by content); anything else is run as an
already-built helper. FLUID_PACKAGE overrides where FluidKit is found.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func fluidPackage() -> URL {
    if let override = ProcessInfo.processInfo.environment["FLUID_PACKAGE"] {
        return URL(fileURLWithPath: override)
    }
    // Sources/fluidctl/main.swift → the package root, for development builds.
    return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

func cacheRoot() -> URL {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return base.appendingPathComponent("Fluid/builds", isDirectory: true)
}

func helper(for path: String) -> URL {
    let url = URL(fileURLWithPath: path)
    guard url.pathExtension == "swift" else { return url }
    let builder = PluginBuilder(fluidPackage: fluidPackage(), cacheRoot: cacheRoot())
    do {
        let output = try builder.build(source: url)
        if !output.cached { FileHandle.standardError.write(Data("built \(output.binary.path)\n".utf8)) }
        return output.binary
    } catch let failure as PluginBuilder.Failure {
        fail(failure.description)
    } catch {
        fail("build failed: \(error)")
    }
}

func render(_ path: String, options: [String]) async {
    var surfaces = Surface.allCases
    var events: [String] = []
    var asJSON = false
    var verbose = false
    var index = 0
    while index < options.count {
        switch options[index] {
        case "--surface":
            index += 1
            guard index < options.count, let surface = Surface(rawValue: options[index]) else { fail(usage) }
            surfaces = [surface]
        case "--event":
            index += 1
            guard index < options.count else { fail(usage) }
            events.append(options[index])
        case "--json":
            asJSON = true
        case "--verbose":
            verbose = true
        default:
            fail(usage)
        }
        index += 1
    }

    let executable = helper(for: path)
    let isVerbose = verbose
    let supervisor: PluginSupervisor
    do {
        supervisor = try PluginSupervisor.make(executable: executable, policy: BackoffPolicy(maxConsecutiveFailures: 0)) { update in
            guard isVerbose else { return }
            switch update {
            case .log(let level, let message): FileHandle.standardError.write(Data("[\(level.rawValue)] \(message)\n".utf8))
            case .state(let state): FileHandle.standardError.write(Data("[state] \(state)\n".utf8))
            case .render: break
            }
        }
    } catch {
        fail("\(error)")
    }
    let wanted = surfaces.filter(supervisor.manifest.surfaces.contains)
    await supervisor.start()

    /// Waits until the plugin has finished handling `count` messages.
    func settle(count: Int, timeout: Double) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case .failed = await supervisor.state { return }
            if await supervisor.settledCount >= count { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    var handled = supervisor.startupMessageCount
    await settle(count: handled, timeout: 30)
    for event in events {
        await supervisor.event(ActionID(event))
        handled += 1
        await settle(count: handled, timeout: 30)
    }

    let views = await supervisor.views
    let state = await supervisor.state
    await supervisor.stop()

    if case .failed(let reason) = state { fail("plugin failed: \(reason)") }
    if asJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let byName = Dictionary(uniqueKeysWithValues: wanted.compactMap { surface in views[surface].map { (surface.rawValue, $0) } })
        if let data = try? encoder.encode(byName) { print(String(decoding: data, as: UTF8.self)) }
        return
    }
    for surface in wanted {
        print("== \(surface.rawValue) ==")
        print(views[surface].map { TreeTextRenderer.render($0) } ?? "(nothing rendered)")
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first, arguments.count >= 2 else { fail(usage) }
let target = arguments[1]

switch command {
case "build":
    print(helper(for: target).path)
case "manifest":
    do {
        let manifest = try PluginProcess.readManifest(executable: helper(for: target))
        print("\(manifest.name) \(manifest.version) (\(manifest.id))")
        print("surfaces: " + manifest.surfaces.map(\.rawValue).joined(separator: ", "))
        for line in SandboxEntitlements.summary(for: manifest) { print("- \(line)") }
    } catch {
        fail("\(error)")
    }
case "render":
    await render(target, options: Array(arguments.dropFirst(2)))
default:
    fail(usage)
}
