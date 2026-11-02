import AppKit
import QuickLookThumbnailing

/// Thumbnails for shelf cards, made lazily at card size and kept only in memory.
/// The cache is emptied a while after the shelf collapses and under memory pressure.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache: NSCache<NSUUID, NSImage> = {
        let cache = NSCache<NSUUID, NSImage>()
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    private var memoryPressure: DispatchSourceMemoryPressure?

    private init() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.removeAll() }
        }
        source.resume()
        memoryPressure = source
    }

    func cached(_ id: UUID) -> NSImage? {
        cache.object(forKey: id as NSUUID)
    }

    func thumbnail(for id: UUID, url: URL, side: CGFloat, scale: CGFloat) async -> NSImage {
        if let image = cached(id) { return image }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: side, height: side),
            scale: scale,
            representationTypes: [.icon, .thumbnail]
        )
        let image: NSImage
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            image = representation.nsImage
        } else {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        let pixels = side * scale
        cache.setObject(image, forKey: id as NSUUID, cost: Int(pixels * pixels * 4))
        return image
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
