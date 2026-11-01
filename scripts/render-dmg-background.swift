#!/usr/bin/env swift
// Renders the background of the installer disk image: dmg/background.png (1x) and
// dmg/background@2x.png. Coordinates are in points with the origin at the top left,
// matching the icon positions passed to create-dmg in scripts/make-dmg.sh.
//
// Usage: swift scripts/render-dmg-background.swift [output-directory]

import AppKit

let windowWidth = 540
let windowHeight = 380
// Finder does not stretch a background picture when the window is enlarged; whatever the
// picture does not cover is drawn white. The canvas is much larger than the window and the
// ground color simply continues, so enlarging the window shows more of the same ground.
let canvasWidth = 1600
let canvasHeight = 1000
// Icon centers in scripts/make-dmg.sh; the arrow is drawn between them.
let appIconX = 140.0
let dropLinkX = 400.0
let iconRowY = 190.0
let iconSize = 128.0

// Finder draws the icon labels itself: white in Dark Mode, black in Light Mode, and the
// image cannot change that. A mid-tone ground keeps both readable.
let groundTop = NSColor(srgbRed: 0.42, green: 0.51, blue: 0.57, alpha: 1)
let groundBottom = NSColor(srgbRed: 0.35, green: 0.43, blue: 0.49, alpha: 1)
let titleColor = NSColor.white
let hintColor = NSColor(srgbRed: 0.93, green: 0.95, blue: 0.96, alpha: 1)

func render(scale: Int, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: canvasWidth * scale,
        pixelsHigh: canvasHeight * scale,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let bitmapContext = NSGraphicsContext(bitmapImageRep: rep) else {
        throw CocoaError(.fileWriteUnknown)
    }
    // Declared size in points, so the 2x file carries 144 dpi.
    rep.size = NSSize(width: canvasWidth, height: canvasHeight)

    let cg = bitmapContext.cgContext
    cg.translateBy(x: 0, y: CGFloat(canvasHeight * scale))
    cg.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

    // Gradient over the window area only; the rest continues with its last color.
    groundBottom.setFill()
    NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight).fill()
    let windowArea = NSRect(x: 0, y: 0, width: canvasWidth, height: windowHeight)
    NSGradient(starting: groundTop, ending: groundBottom)?.draw(in: windowArea, angle: 90)

    drawCentered(
        "Drag ConvinientScroll to Applications",
        y: 44,
        font: .systemFont(ofSize: 21, weight: .semibold),
        color: titleColor
    )

    drawArrow(from: appIconX + iconSize / 2 + 22, to: dropLinkX - iconSize / 2 - 22, y: iconRowY)

    drawCentered(
        "Already running? Quit it from the menu bar first, then choose Replace.",
        y: 318,
        font: .systemFont(ofSize: 12.5, weight: .regular),
        color: hintColor
    )
    drawCentered(
        "Don\u{2019}t open it from this window.",
        y: 338,
        font: .systemFont(ofSize: 12.5, weight: .regular),
        color: hintColor
    )

    NSGraphicsContext.current = nil
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url)
}

func drawCentered(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let size = (text as NSString).size(withAttributes: attributes)
    (text as NSString).draw(
        at: NSPoint(x: (CGFloat(windowWidth) - size.width) / 2, y: y - size.height / 2),
        withAttributes: attributes
    )
}

func drawArrow(from startX: CGFloat, to endX: CGFloat, y: CGFloat) {
    NSColor.white.withAlphaComponent(0.9).setStroke()

    let shaft = NSBezierPath()
    shaft.lineWidth = 3.5
    shaft.lineCapStyle = .round
    shaft.setLineDash([0.1, 9], count: 2, phase: 0)
    shaft.move(to: NSPoint(x: startX, y: y))
    shaft.line(to: NSPoint(x: endX - 6, y: y))
    shaft.stroke()

    let head = NSBezierPath()
    head.lineWidth = 3.5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.move(to: NSPoint(x: endX - 14, y: y - 15))
    head.line(to: NSPoint(x: endX + 2, y: y))
    head.line(to: NSPoint(x: endX - 14, y: y + 15))
    head.stroke()
}

let outputDirectory = URL(
    fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg",
    isDirectory: true
)
do {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    try render(scale: 1, to: outputDirectory.appendingPathComponent("background.png"))
    try render(scale: 2, to: outputDirectory.appendingPathComponent("background@2x.png"))
    print("Wrote background.png and background@2x.png to \(outputDirectory.path)")
} catch {
    FileHandle.standardError.write(Data("Cannot render DMG background: \(error)\n".utf8))
    exit(1)
}
