import Foundation

/// Formats a plugin-supplied `Double` the way Vee's labels do: whole numbers
/// print bare (`42`), everything else to two decimal places (`3.14`).
public enum CompactNumber {
    /// Exists because the obvious one-liner — `String(Int(v))` — TRAPS on any
    /// finite value ≥ ~9.2e18 (`Int.init(Double)` aborts on overflow), and
    /// these values come straight from plugin output: `sparkline=1,2,1e19`
    /// must never crash the app. One shared helper so the next label site
    /// can't reintroduce the crash (cf. `ControlReinvocation.format`'s
    /// magnitude guard, the same idea for shell-facing values).
    public static func label(_ v: Double) -> String {
        if v == v.rounded(), let whole = Int(exactly: v.rounded()) { return String(whole) }
        return String(format: "%.2f", v)
    }
}
