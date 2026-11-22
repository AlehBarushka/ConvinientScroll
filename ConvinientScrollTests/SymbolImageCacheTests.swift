import AppKit
import Testing
@testable import MacToolkit

@Suite("SymbolImageCache")
@MainActor
struct SymbolImageCacheTests {
    @Test func loadsEachSymbolOnce() {
        var loads: [String] = []
        let cache = SymbolImageCache { name, _ in
            loads.append(name)
            return NSImage(size: NSSize(width: 14, height: 14))
        }
        let first = cache.image("memorychip", pointSize: 13)
        let second = cache.image("memorychip", pointSize: 13)
        #expect(first != nil)
        #expect(first === second)
        #expect(loads == ["memorychip"])
    }

    @Test func pointSizeIsPartOfTheKey() {
        var loads = 0
        let cache = SymbolImageCache { _, _ in
            loads += 1
            return NSImage(size: NSSize(width: 14, height: 14))
        }
        _ = cache.image("trackpad", pointSize: 13)
        _ = cache.image("trackpad", pointSize: 14)
        #expect(loads == 2)
    }

    @Test func remembersMissingSymbols() {
        var loads = 0
        let cache = SymbolImageCache { _, _ in
            loads += 1
            return nil
        }
        #expect(cache.image("mouse", pointSize: 14) == nil)
        #expect(cache.image("mouse", pointSize: 14) == nil)
        #expect(loads == 1)
    }

    @Test func liveImagesAreTemplates() {
        #expect(SymbolImageCache().image("memorychip", pointSize: 13)?.isTemplate == true)
    }
}
