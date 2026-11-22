import AppKit

/// Every new NSImage is rasterized from its vector glyph again for each display's menu bar
/// snapshot, so the menu bar item reuses one image per symbol and size.
@MainActor
final class SymbolImageCache {
    typealias Load = (_ name: String, _ pointSize: CGFloat) -> NSImage?

    private struct Key: Hashable {
        var name: String
        var pointSize: CGFloat
    }

    private let load: Load
    private var images: [Key: NSImage?] = [:]

    init(load: @escaping Load = SymbolImageCache.loadSymbol) {
        self.load = load
    }

    func image(_ name: String, pointSize: CGFloat) -> NSImage? {
        let key = Key(name: name, pointSize: pointSize)
        if let cached = images[key] { return cached }
        let image = load(name, pointSize)
        images[key] = .some(image)
        return image
    }

    nonisolated static func loadSymbol(_ name: String, pointSize: CGFloat) -> NSImage? {
        let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        let image = base?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)) ?? base
        image?.isTemplate = true
        return image
    }
}
