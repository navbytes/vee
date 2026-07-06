import Foundation

/// GitHub-style `:shortcode:` → emoji substitution (the `emojize` param, on by
/// default). Ships a curated common subset; unknown shortcodes are left intact.
/// The table is intentionally small and extensible — full coverage can be added
/// later without changing callers.
enum Emoji {
    static let table: [String: String] = [
        "smile": "😄", "grin": "😁", "joy": "😂", "wink": "😉",
        "rocket": "🚀", "warning": "⚠️", "white_check_mark": "✅", "heavy_check_mark": "✔️",
        "x": "❌", "bug": "🐛", "fire": "🔥", "star": "⭐️", "sparkles": "✨",
        "heart": "❤️", "tada": "🎉", "zap": "⚡️", "coffee": "☕️",
        "+1": "👍", "-1": "👎", "eyes": "👀", "wave": "👋",
        "sunny": "☀️", "cloud": "☁️", "rain": "🌧️", "snowflake": "❄️",
        "computer": "💻", "bell": "🔔", "no_bell": "🔕", "email": "📧",
        "calendar": "📅", "clock": "🕐", "hourglass": "⏳", "lock": "🔒", "unlock": "🔓",
        "green_circle": "🟢", "red_circle": "🔴", "yellow_circle": "🟡", "large_blue_circle": "🔵",
        "battery": "🔋", "wifi": "📶", "moon": "🌙", "thermometer": "🌡️",
        // Faces & gestures
        "smiley": "😃", "laughing": "😆", "blush": "😊", "heart_eyes": "😍",
        "thinking": "🤔", "sob": "😭", "rage": "😡", "cry": "😢", "sweat_smile": "😅",
        "clap": "👏", "pray": "🙏", "muscle": "💪", "point_right": "👉", "ok_hand": "👌",
        // Status & symbols
        "heavy_multiplication_x": "✖️", "heavy_plus_sign": "➕", "heavy_minus_sign": "➖",
        "question": "❓", "exclamation": "❗️", "bangbang": "‼️", "recycle": "♻️",
        "arrow_up": "⬆️", "arrow_down": "⬇️", "arrow_left": "⬅️", "arrow_right": "➡️",
        "arrows_counterclockwise": "🔄", "hourglass_flowing_sand": "⏳", "stopwatch": "⏱️",
        "check": "✅", "heavy_exclamation_mark": "❗️", "no_entry": "⛔️", "no_entry_sign": "🚫",
        // Objects & tech
        "gear": "⚙️", "wrench": "🔧", "hammer": "🔨", "package": "📦", "memo": "📝",
        "chart_with_upwards_trend": "📈", "chart_with_downwards_trend": "📉", "bar_chart": "📊",
        "floppy_disk": "💾", "cd": "💿", "iphone": "📱", "keyboard": "⌨️", "printer": "🖨️",
        "bulb": "💡", "flashlight": "🔦", "mag": "🔍", "key": "🔑", "link": "🔗", "pushpin": "📌",
        "moneybag": "💰", "dollar": "💵", "credit_card": "💳", "gem": "💎", "crown": "👑",
        // Nature & weather
        "zap_cloud": "🌩️", "umbrella": "☔️", "snowman": "⛄️", "ocean": "🌊", "droplet": "💧",
        "seedling": "🌱", "leaves": "🍃", "maple_leaf": "🍁", "cactus": "🌵", "dog": "🐶", "cat": "🐱",
        // Food & travel
        "pizza": "🍕", "hamburger": "🍔", "beer": "🍺", "wine_glass": "🍷", "cake": "🍰",
        "car": "🚗", "airplane": "✈️", "rocket_ship": "🚀", "house": "🏠", "office": "🏢",
        // Circles & squares
        "white_circle": "⚪️", "black_circle": "⚫️", "orange_circle": "🟠", "purple_circle": "🟣",
        "brown_circle": "🟤", "green_square": "🟩", "red_square": "🟥", "yellow_square": "🟨"
    ]

    // Compile-time-constant pattern; cannot fail at runtime.
    // swiftlint:disable:next force_try
    private static let pattern = try! NSRegularExpression(pattern: ":([a-z0-9_+-]+):", options: [])

    /// Replaces known `:shortcode:` tokens with their emoji. No-op if the string
    /// contains no colon.
    static func replace(_ text: String) -> String {
        guard text.contains(":") else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let code = ns.substring(with: match.range(at: 1))
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            if let emoji = table[code] {
                result += emoji
            } else {
                result += ns.substring(with: match.range) // leave unknown intact
            }
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
