import AppKit
import VeePluginFormat

/// Resolves a menu line's image to an `NSImage`: SF Symbols (`sfimage`, with
/// optional color/size), base64 `image`, or `templateImage`.
public enum SymbolImageFactory {
    /// Every render re-creates every row's image (SF Symbol configuration or a
    /// base64 decode), even though a plugin's own output — and therefore its
    /// resolved images — is byte-identical across most refreshes. Cache the
    /// final, fully-configured image keyed by everything that affects its
    /// appearance; NSImage is safe to share across menu items and the status
    /// bar button, and NSCache evicts under memory pressure on its own.
    /// `nonisolated(unsafe)` because NSCache isn't Sendable but Apple documents
    /// it as thread-safe (items can be added, removed, and queried from
    /// different threads without locking) — precisely the external
    /// synchronization the strict-concurrency opt-out exists for.
    nonisolated(unsafe) private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        return cache
    }()

    public static func image(for params: LineParams) -> NSImage? {
        if let symbol = params.swiftbar.sfimage {
            let key = sfCacheKey(name: symbol, params: params.swiftbar)
            if let cached = cache.object(forKey: key) { return cached }
            guard let image = sfSymbol(named: symbol, params: params.swiftbar) else { return nil }
            cache.setObject(image, forKey: key)
            return image
        }
        if let base64 = params.templateImage {
            let key = "tpl|\(base64)" as NSString
            if let cached = cache.object(forKey: key) { return cached }
            if let image = decode(base64) {
                image.isTemplate = true
                cache.setObject(image, forKey: key)
                return image
            }
        }
        if let base64 = params.image {
            let key = "img|\(base64)" as NSString
            if let cached = cache.object(forKey: key) { return cached }
            if let image = decode(base64) {
                cache.setObject(image, forKey: key)
                return image
            }
        }
        return nil
    }

    /// Captures every input `sfSymbol(named:params:)` reads, so two calls that
    /// would render identically hit the same cache entry and two that wouldn't
    /// never collide.
    private static func sfCacheKey(name: String, params: SwiftBarParams) -> NSString {
        let colors = (params.sfcolor ?? []).map(colorToken).joined(separator: ",")
        return "sf|\(name)|\(params.sfsize ?? -1)|\(params.sfconfig ?? "")|\(colors)" as NSString
    }

    private static func colorToken(_ color: VeeColor) -> String {
        switch color {
        case .named(let name): return "n:\(name)"
        case .rgb(let r, let g, let b, let a): return "r:\(r),\(g),\(b),\(a)"
        }
    }

    private static func sfSymbol(named name: String, params: SwiftBarParams) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        var config = NSImage.SymbolConfiguration.preferringMonochrome()
        let sfconfig = SFSymbolConfig.parse(params.sfconfig)

        // Point size (from sfsize) and weight (from sfconfig).
        if params.sfsize != nil || sfconfig?.nsWeight != nil {
            let size = CGFloat(params.sfsize ?? Double(NSFont.systemFontSize))
            config = config.applying(NSImage.SymbolConfiguration(pointSize: size, weight: sfconfig?.nsWeight ?? .regular))
        }
        // Symbol scale from sfconfig (small/medium/large).
        if let scale = sfconfig?.nsScale {
            config = config.applying(NSImage.SymbolConfiguration(scale: scale))
        }

        if let colors = params.sfcolor, !colors.isEmpty {
            let nsColors = colors.compactMap(ColorResolver.nsColor(for:))
            if !nsColors.isEmpty {
                config = config.applying(NSImage.SymbolConfiguration(paletteColors: nsColors))
                image.isTemplate = false
            }
        } else {
            image.isTemplate = true // tint with the menu bar
        }
        return image.withSymbolConfiguration(config) ?? image
    }

    private static func decode(_ base64: String) -> NSImage? {
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return nil }
        return NSImage(data: data)
    }
}
