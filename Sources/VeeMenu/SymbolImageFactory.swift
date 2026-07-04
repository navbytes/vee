import AppKit
import VeePluginFormat

/// Resolves a menu line's image to an `NSImage`: SF Symbols (`sfimage`, with
/// optional color/size), base64 `image`, or `templateImage`.
public enum SymbolImageFactory {
    public static func image(for params: LineParams) -> NSImage? {
        if let symbol = params.swiftbar.sfimage {
            return sfSymbol(named: symbol, params: params.swiftbar)
        }
        if let base64 = params.templateImage, let image = decode(base64) {
            image.isTemplate = true
            return image
        }
        if let base64 = params.image, let image = decode(base64) {
            return image
        }
        return nil
    }

    private static func sfSymbol(named name: String, params: SwiftBarParams) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        var config = NSImage.SymbolConfiguration.preferringMonochrome()
        if let size = params.sfsize {
            config = config.applying(NSImage.SymbolConfiguration(pointSize: CGFloat(size), weight: .regular))
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
