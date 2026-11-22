import AppKit
import Testing
@testable import MacToolkit

@Suite("MenuBarTitle")
struct MenuBarTitleTests {
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    private let image: (String) -> NSImage? = { _ in NSImage(size: NSSize(width: 14, height: 14)) }
    private let mem = MenuBarSegment(symbol: "memorychip", text: "54%", reservedCharacters: 4, tint: .none, accessibility: "54% memory used, pressure normal")
    private let cpu = MenuBarSegment(symbol: "thermometer.medium", text: "62°", reservedCharacters: 4, tint: .none, accessibility: "CPU 62°, thermal pressure nominal")

    @Test func paddsOnTheRight() {
        #expect(MenuBarTitle.paddedText(mem) == "54%\u{2007}")
        var full = mem
        full.text = "100%"
        #expect(MenuBarTitle.paddedText(full) == "100%")
        var long = mem
        long.text = "12345%"
        #expect(MenuBarTitle.paddedText(long) == "12345%")
    }

    @Test func emptyWithoutSegments() {
        #expect(MenuBarTitle.attributedTitle([], font: font, symbol: image).length == 0)
    }

    @Test func segmentsKeepOrder() {
        let title = MenuBarTitle.attributedTitle([mem, cpu], font: font, symbol: image)
        #expect(title.string == " \u{FFFC}\u{2009}54%\u{2007} \u{FFFC}\u{2009}62°\u{2007}")
    }

    @Test func missingSymbolKeepsText() {
        let title = MenuBarTitle.attributedTitle([mem], font: font, symbol: { _ in nil })
        #expect(title.string == " \u{2009}54%\u{2007}")
    }

    @Test func tintStaysInsideItsSegment() {
        var warm = mem
        warm.tint = .warning
        var hot = cpu
        hot.tint = .critical
        let title = MenuBarTitle.attributedTitle([warm, hot], font: font, symbol: image)
        let color = { (index: Int) in title.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor }
        // " \u{FFFC}\u{2009}54%\u{2007} \u{FFFC}\u{2009}62°\u{2007}"
        #expect(color(0) == nil)
        #expect([1, 3, 4, 5].allSatisfy { color($0) == NSColor.systemYellow })
        #expect(color(7) == nil)
        #expect([8, 10, 11, 12].allSatisfy { color($0) == NSColor.systemRed })
    }

    @Test func noColorWithoutTint() {
        let title = MenuBarTitle.attributedTitle([mem, cpu], font: font, symbol: image)
        var colored = false
        title.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: title.length)) { value, _, _ in
            if value != nil { colored = true }
        }
        #expect(!colored)
    }

    @Test func widthDoesNotDependOnDigits() {
        func width(_ memory: String, _ celsius: String) -> CGFloat {
            var m = mem
            m.text = memory
            var c = cpu
            c.text = celsius
            return MenuBarTitle.attributedTitle([m, c], font: font, symbol: image).size().width
        }
        #expect(abs(width("9%", "58°") - width("100%", "101°")) < 0.5)
    }

    @Test func accessibilityJoinsSegments() {
        #expect(MenuBarTitle.accessibilityValue([mem, cpu]) == "54% memory used, pressure normal, CPU 62°, thermal pressure nominal")
    }
}
