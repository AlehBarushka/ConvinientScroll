import AppKit

nonisolated enum MenuBarTitle {
    static let figureSpace: Character = "\u{2007}"
    static let figureDash: Character = "\u{2012}"
    static let symbolGap = "\u{2009}"
    static let segmentGap = " "

    /// Figure spaces and figure dashes are as wide as digits in a monospaced-digit font, so padding
    /// to a fixed character count keeps the item's width when the value gains or loses a digit.
    static func paddedText(_ segment: MenuBarSegment) -> String {
        let missing = segment.reservedCharacters - segment.text.count
        guard missing > 0 else { return segment.text }
        return segment.text + String(repeating: figureSpace, count: missing)
    }

    static func attributedTitle(_ segments: [MenuBarSegment], font: NSFont, symbol: (String) -> NSImage?) -> NSAttributedString {
        let title = NSMutableAttributedString()
        for segment in segments {
            title.append(NSAttributedString(string: segmentGap))
            let start = title.length
            if let image = symbol(segment.symbol) {
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = NSRect(
                    x: 0,
                    y: ((font.capHeight - image.size.height) / 2).rounded(),
                    width: image.size.width,
                    height: image.size.height
                )
                title.append(NSAttributedString(attachment: attachment))
            }
            title.append(NSAttributedString(string: symbolGap + paddedText(segment)))
            if let color = color(segment.tint) {
                title.addAttribute(.foregroundColor, value: color, range: NSRange(location: start, length: title.length - start))
            }
        }
        title.addAttribute(.font, value: font, range: NSRange(location: 0, length: title.length))
        return title
    }

    static func accessibilityValue(_ segments: [MenuBarSegment]) -> String {
        segments.map(\.accessibility).joined(separator: ", ")
    }

    private static func color(_ tint: MenuBarTint) -> NSColor? {
        switch tint {
        case .none: nil
        case .warning: .systemYellow
        case .critical: .systemRed
        }
    }
}
