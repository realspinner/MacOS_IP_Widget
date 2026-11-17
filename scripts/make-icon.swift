#!/usr/bin/env swift
import AppKit
import Foundation

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outputPath, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) {
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.02
    let corner = size * 0.225
    let plate = NSBezierPath(
        roundedRect: rect.insetBy(dx: inset, dy: inset),
        xRadius: corner,
        yRadius: corner
    )

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.25, green: 0.53, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.35, green: 0.27, blue: 0.92, alpha: 1),
    ])!
    gradient.draw(in: plate, angle: -60)

    NSColor.white.withAlphaComponent(0.20).setStroke()
    plate.lineWidth = max(1, size * 0.006)
    plate.stroke()

    let globe = rect.insetBy(dx: size * 0.255, dy: size * 0.255)
    let stroke = size * 0.030
    NSColor.white.withAlphaComponent(0.96).setStroke()

    let circle = NSBezierPath(ovalIn: globe)
    circle.lineWidth = stroke
    circle.stroke()

    let meridianWidth = globe.width * 0.46
    let meridian = NSBezierPath(ovalIn: NSRect(
        x: globe.midX - meridianWidth / 2,
        y: globe.minY,
        width: meridianWidth,
        height: globe.height
    ))
    meridian.lineWidth = stroke
    meridian.stroke()

    NSGraphicsContext.saveGraphicsState()
    circle.addClip()
    for offset in [-0.30, 0.0, 0.30] {
        let y = globe.midY + globe.height * offset
        let line = NSBezierPath()
        line.move(to: NSPoint(x: globe.minX - stroke, y: y))
        line.line(to: NSPoint(x: globe.maxX + stroke, y: y))
        line.lineWidth = stroke
        line.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()

    let dotSize = size * 0.155
    let dot = NSRect(
        x: size * 0.705,
        y: size * 0.095,
        width: dotSize,
        height: dotSize
    )
    let ring = NSBezierPath(ovalIn: dot.insetBy(dx: -dotSize * 0.10, dy: -dotSize * 0.10))
    NSColor.white.withAlphaComponent(0.92).setStroke()
    ring.lineWidth = size * 0.016
    ring.stroke()

    NSColor(srgbRed: 0.22, green: 0.84, blue: 0.45, alpha: 1).setFill()
    NSBezierPath(ovalIn: dot).fill()
}

func writePNG(pixels: Int, name: String) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "icon", code: 1)
    }
    bitmap.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.cgContext.setAllowsAntialiasing(true)
    NSGraphicsContext.current?.cgContext.setShouldAntialias(true)
    drawIcon(size: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 2)
    }
    try data.write(to: URL(fileURLWithPath: outputPath).appendingPathComponent(name))
}

let variants: [(pixels: Int, name: String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for variant in variants {
    try writePNG(pixels: variant.pixels, name: variant.name)
}
print("Iconset written to \(outputPath)")
