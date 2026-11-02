#!/usr/bin/env swift
// Renders the app icon into ConvinientScroll/Assets.xcassets/AppIcon.appiconset: a blue
// tile with the black shelf hanging from its top edge, three files on it, and a mouse
// below. Every size is drawn from vectors, not scaled down from the largest one.
//
// Usage: swift scripts/render-app-icon.swift [appiconset-directory]

import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : root.appending(path: "ConvinientScroll/Assets.xcassets/AppIcon.appiconset")

// Geometry on a 1024-point canvas, following the macOS icon grid (824-point tile).
let canvas: CGFloat = 1024
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tileRadius: CGFloat = 185

let blueTop = NSColor(srgbRed: 0.22, green: 0.42, blue: 0.95, alpha: 1)
let blueBottom = NSColor(srgbRed: 0.10, green: 0.16, blue: 0.48, alpha: 1)
let fileColors = [
    NSColor(srgbRed: 0.98, green: 0.36, blue: 0.33, alpha: 1),
    NSColor(srgbRed: 1.00, green: 0.78, blue: 0.20, alpha: 1),
    NSColor(srgbRed: 0.30, green: 0.85, blue: 0.50, alpha: 1)
]

/// The shelf: a shape hanging from `top`, rounded at the bottom, with concave ears.
func shelfPath(centerX: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat, ear: CGFloat, radius: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    let left = centerX - width / 2 - ear
    let right = centerX + width / 2 + ear
    let bottom = top - height
    p.move(to: CGPoint(x: left, y: top))
    p.curve(to: CGPoint(x: left + ear, y: top - ear),
            controlPoint1: CGPoint(x: left + ear * 0.55, y: top), controlPoint2: CGPoint(x: left + ear, y: top - ear * 0.45))
    p.line(to: CGPoint(x: left + ear, y: bottom + radius))
    p.curve(to: CGPoint(x: left + ear + radius, y: bottom),
            controlPoint1: CGPoint(x: left + ear, y: bottom + radius * 0.45), controlPoint2: CGPoint(x: left + ear + radius * 0.45, y: bottom))
    p.line(to: CGPoint(x: right - ear - radius, y: bottom))
    p.curve(to: CGPoint(x: right - ear, y: bottom + radius),
            controlPoint1: CGPoint(x: right - ear - radius * 0.45, y: bottom), controlPoint2: CGPoint(x: right - ear, y: bottom + radius * 0.45))
    p.line(to: CGPoint(x: right - ear, y: top - ear))
    p.curve(to: CGPoint(x: right, y: top),
            controlPoint1: CGPoint(x: right - ear, y: top - ear * 0.45), controlPoint2: CGPoint(x: right - ear * 0.55, y: top))
    p.close()
    return p
}

func drawIcon() {
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tileRadius, yRadius: tileRadius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 20
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    blueBottom.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSGradient(starting: blueTop, ending: blueBottom)?.draw(in: tile, angle: -90)

    NSColor.black.setFill()
    shelfPath(centerX: tile.midX, top: tile.maxY, width: 600, height: 380, ear: 56, radius: 96).fill()

    for (index, color) in fileColors.enumerated() {
        let x = tile.midX - 230 + CGFloat(index) * 165
        let top = tile.maxY - 170
        color.setFill()
        NSBezierPath(roundedRect: CGRect(x: x, y: top - 160, width: 130, height: 160), xRadius: 22, yRadius: 22).fill()
        // Folded corner.
        let fold = NSBezierPath()
        fold.move(to: CGPoint(x: x + 90, y: top))
        fold.line(to: CGPoint(x: x + 130, y: top - 40))
        fold.line(to: CGPoint(x: x + 90, y: top - 40))
        fold.close()
        NSColor(white: 1, alpha: 0.45).setFill()
        fold.fill()
    }

    // The mouse is drawn as paths: an SF Symbol would be rasterized before the
    // context is scaled and come out blurred at some sizes.
    let mouse = CGRect(x: tile.midX - 62, y: tile.minY + 112, width: 124, height: 196)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: mouse, xRadius: 62, yRadius: 62).fill()
    let buttons = NSBezierPath()
    buttons.move(to: CGPoint(x: mouse.minX, y: mouse.maxY - 78))
    buttons.line(to: CGPoint(x: mouse.maxX, y: mouse.maxY - 78))
    buttons.move(to: CGPoint(x: mouse.midX, y: mouse.maxY))
    buttons.line(to: CGPoint(x: mouse.midX, y: mouse.maxY - 78))
    buttons.lineWidth = 12
    blueBottom.setStroke()
    buttons.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

func render(pixels: Int, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw CocoaError(.fileWriteUnknown)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url)
}

// Point sizes of a macOS app icon, each at 1x and 2x.
let pointSizes = [16, 32, 128, 256, 512]
var images: [[String: String]] = []
let fm = FileManager.default
try fm.createDirectory(at: output, withIntermediateDirectories: true)
for old in try fm.contentsOfDirectory(at: output, includingPropertiesForKeys: nil) where old.pathExtension == "png" {
    try fm.removeItem(at: old)
}
for size in pointSizes {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: size * scale, to: output.appending(path: name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(size)x\(size)"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appending(path: "Contents.json"))
print("Wrote \(images.count) icon images to \(output.path)")
