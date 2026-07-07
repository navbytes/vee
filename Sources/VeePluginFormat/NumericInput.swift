import Foundation

/// Sanitises free-text input for a `.number` `<xbar.var>` field as the user
/// types, so a numeric preference can't be saved with letters or stray symbols.
/// Pure and Sendable — unit-tested without any UI.
public enum NumericInput {
    /// Reduces a string to a valid decimal number: an optional leading minus,
    /// ASCII digits, and at most one decimal point. Everything else is dropped.
    ///
    /// Applied incrementally on each keystroke, so partial input like `"-"` or
    /// `"1."` is preserved while the user is still typing.
    public static func sanitize(_ input: String) -> String {
        var result = ""
        var seenDot = false
        for (index, character) in input.enumerated() {
            if character == "-", index == 0 {
                result.append(character)
            } else if character == ".", !seenDot {
                seenDot = true
                result.append(character)
            } else if character.isASCII, character.isNumber {
                result.append(character)
            }
        }
        return result
    }
}
