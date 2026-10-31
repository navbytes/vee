@_exported import FluidProtocol

/// Anything a plugin can put in a view body.
///
/// A view resolves to zero or more `ViewNode`s, registering the closures it
/// carries with the `RenderContext` as it goes. Returning an array lets
/// conditionals and loops flatten into their parent without wrapper nodes.
@MainActor
public protocol FluidView {
    func resolve(in context: RenderContext) -> [ViewNode]
}

/// What a `@ViewBuilder` body produces.
public typealias ViewContent = [any FluidView]

extension Array: FluidView where Element == any FluidView {
    public func resolve(in context: RenderContext) -> [ViewNode] {
        flatMap { $0.resolve(in: context) }
    }
}

/// Builds view bodies the way SwiftUI does: plain statements, `if`/`else`,
/// `switch`, optionals and `for` loops.
@resultBuilder
public enum ViewBuilder {
    @MainActor public static func buildExpression(_ view: any FluidView) -> ViewContent { [view] }
    @MainActor public static func buildBlock(_ parts: ViewContent...) -> ViewContent { parts.flatMap { $0 } }
    @MainActor public static func buildOptional(_ part: ViewContent?) -> ViewContent { part ?? [] }
    @MainActor public static func buildEither(first part: ViewContent) -> ViewContent { part }
    @MainActor public static func buildEither(second part: ViewContent) -> ViewContent { part }
    @MainActor public static func buildArray(_ parts: [ViewContent]) -> ViewContent { parts.flatMap { $0 } }
    @MainActor public static func buildLimitedAvailability(_ part: ViewContent) -> ViewContent { part }
}

/// Collects the closures a render registers, so an `event` can find its handler.
///
/// Ids are derived from what the view says about itself — a row's key plus the
/// action's title, a button's title — not from render order, so a click that
/// lands after a re-render still reaches the same closure. Collisions get a
/// `#2`, `#3` suffix rather than silently replacing an earlier handler.
@MainActor
public final class RenderContext {
    public typealias Handler = @MainActor (EventValue?) async throws -> Void

    public private(set) var handlers: [ActionID: Handler] = [:]

    public init() {}

    public func register(_ base: String, _ handler: @escaping Handler) -> ActionID {
        var id = ActionID(base)
        var suffix = 2
        while handlers[id] != nil {
            id = ActionID("\(base)#\(suffix)")
            suffix += 1
        }
        handlers[id] = handler
        return id
    }
}
