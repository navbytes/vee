import Foundation

/// Accumulates the stdout lines of a streamable plugin and emits a complete
/// output block each time the `~~~` separator is seen. SwiftBar resets the menu
/// on every `~~~`, so each block is a full menu render.
public struct StreamAccumulator {
    public static let separator = "~~~"

    private var buffer: [String] = []

    public init() {}

    /// Consumes one line. Returns the accumulated block (as a single string)
    /// when the line is a `~~~` separator, otherwise `nil`.
    public mutating func consume(_ line: String) -> String? {
        if line == Self.separator {
            let block = buffer.joined(separator: "\n")
            buffer.removeAll(keepingCapacity: true)
            return block
        }
        buffer.append(line)
        return nil
    }

    /// Emits any remaining buffered lines (e.g. when the stream ends without a
    /// trailing separator). Returns `nil` if nothing is buffered.
    public mutating func flush() -> String? {
        guard !buffer.isEmpty else { return nil }
        let block = buffer.joined(separator: "\n")
        buffer.removeAll(keepingCapacity: true)
        return block
    }
}
