/// A Fluid plugin: a class whose properties are its state and whose view
/// properties describe what each surface shows.
///
/// ```swift
/// @main
/// final class Clock: FluidPlugin {
///     static let manifest = Manifest(id: "dev.example.clock", name: "Clock", triggers: [.launch, .every(.seconds(1))])
///     var now = Date()
///     func refresh() async throws { now = Date() }
///     var menuBar: ViewContent { Label(now.formatted(date: .omitted, time: .shortened), symbol: "clock") }
/// }
/// ```
///
/// The runtime calls `refresh()` when a trigger fires, runs action closures
/// when the user acts, and re-renders after each. A render that comes out the
/// same as the last one is not sent.
@MainActor
public protocol FluidPlugin: AnyObject {
    static var manifest: Manifest { get }
    init()
    /// Fetch or recompute state. Thrown errors are logged to the host, and the
    /// previous render stays on screen.
    func refresh() async throws
    @ViewBuilder var menuBar: ViewContent { get }
    @ViewBuilder var panel: ViewContent { get }
}

extension FluidPlugin {
    public func refresh() async throws {}
    public var menuBar: ViewContent { [Label(Self.manifest.name, symbol: "puzzlepiece.extension")] }
    public var panel: ViewContent { [] }

    /// The entry point `@main` uses. `--manifest` prints the manifest as JSON
    /// and exits; anything else starts the protocol loop on stdin/stdout.
    public static func main() async {
        if CommandLine.arguments.contains("--manifest") {
            StdioTransport.printManifest(manifest)
            return
        }
        let transport = StdioTransport()
        let runtime = PluginRuntime(plugin: Self(), send: transport.send)
        for await message in transport.incoming() {
            if await !runtime.handle(message) { break }
        }
    }
}
