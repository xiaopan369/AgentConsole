#!/usr/bin/env swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assetsDir = root.appendingPathComponent("Assets", isDirectory: true)
let iconsetDir = assetsDir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

func savePNG(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG for \(url.path)"])
    }
    try png.write(to: url)
}

func makeBitmap(size: Int, draw: (CGRect) -> Void) throws -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "IconGeneration", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap \(size)x\(size)"])
    }
    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(CGRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

func roundedPolygonPath(points: [CGPoint], lineWidth: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    guard let first = points.first else { return path }
    path.move(to: first)
    for point in points.dropFirst() {
        path.line(to: point)
    }
    return path
}

func drawAppIcon(in rect: CGRect) {
    let size = rect.width
    let scale = size / 1024
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
    }
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: rect.minX + x * scale, y: rect.minY + y * scale, width: w * scale, height: h * scale)
    }

    NSColor.clear.setFill()
    NSBezierPath(rect: rect).fill()

    let shadow = NSShadow()
    shadow.shadowBlurRadius = 36 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -16 * scale)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.set()

    let background = NSBezierPath(roundedRect: r(86, 72, 852, 852), xRadius: 220 * scale, yRadius: 220 * scale)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 1.0, green: 1.0, blue: 0.985, alpha: 1),
        NSColor(calibratedRed: 0.955, green: 0.982, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.985, green: 0.988, blue: 0.975, alpha: 1),
    ])
    gradient?.draw(in: background, angle: -35)

    NSGraphicsContext.saveGraphicsState()
    background.addClip()
    NSColor(calibratedRed: 0.20, green: 0.56, blue: 1.0, alpha: 0.10).setFill()
    NSBezierPath(ovalIn: r(156, 106, 420, 420)).fill()
    NSColor(calibratedRed: 0.22, green: 0.90, blue: 0.66, alpha: 0.10).setFill()
    NSBezierPath(ovalIn: r(520, 510, 360, 360)).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSShadow().set()
    NSColor.black.withAlphaComponent(0.09).setStroke()
    background.lineWidth = 3 * scale
    background.stroke()

    let glyphShadow = NSShadow()
    glyphShadow.shadowBlurRadius = 20 * scale
    glyphShadow.shadowOffset = NSSize(width: 0, height: -6 * scale)
    glyphShadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
    glyphShadow.set()

    let left = roundedPolygonPath(points: [p(420, 336), p(294, 512), p(420, 688)], lineWidth: 58 * scale)
    NSColor(calibratedRed: 0.05, green: 0.45, blue: 0.92, alpha: 1).setStroke()
    left.stroke()

    let right = roundedPolygonPath(points: [p(604, 336), p(730, 512), p(604, 688)], lineWidth: 58 * scale)
    NSColor(calibratedRed: 0.10, green: 0.72, blue: 0.53, alpha: 1).setStroke()
    right.stroke()

    let cursor = NSBezierPath(roundedRect: r(444, 633, 136, 44), xRadius: 22 * scale, yRadius: 22 * scale)
    NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.18, alpha: 0.82).setFill()
    cursor.fill()

    let bridge = roundedPolygonPath(points: [p(424, 512), p(600, 512)], lineWidth: 32 * scale)
    NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.24, alpha: 0.36).setStroke()
    bridge.stroke()

    NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.18, alpha: 0.86).setFill()
    NSBezierPath(ovalIn: r(488, 488, 48, 48)).fill()
}

func drawMenuBarGlyph(in rect: CGRect, color: NSColor) {
    let size = rect.width
    let scale = size / 18
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
    }

    color.setStroke()
    color.setFill()

    let left = roundedPolygonPath(points: [p(7.2, 3.4), p(3.6, 9.0), p(7.2, 14.6)], lineWidth: 2.15 * scale)
    left.stroke()

    let right = roundedPolygonPath(points: [p(10.8, 3.4), p(14.4, 9.0), p(10.8, 14.6)], lineWidth: 2.15 * scale)
    right.stroke()

    let cursor = roundedPolygonPath(points: [p(7.45, 11.45), p(10.55, 11.45)], lineWidth: 1.7 * scale)
    cursor.stroke()

    let bridge = roundedPolygonPath(points: [p(7.45, 8.4), p(10.55, 8.4)], lineWidth: 1.45 * scale)
    bridge.stroke()

    NSBezierPath(ovalIn: CGRect(x: rect.minX + 8.15 * scale, y: rect.minY + 7.55 * scale, width: 1.7 * scale, height: 1.7 * scale)).fill()
}

func drawMenuBarIcon(in rect: CGRect) {
    NSColor.clear.setFill()
    NSBezierPath(rect: rect).fill()
    drawMenuBarGlyph(in: rect, color: .black)
}

let appIcon1024 = try makeBitmap(size: 1024, draw: drawAppIcon)
try savePNG(appIcon1024, to: assetsDir.appendingPathComponent("AppIcon-1024.png", isDirectory: false))
try savePNG(try makeBitmap(size: 256, draw: drawAppIcon), to: assetsDir.appendingPathComponent("AppMiniwindow.png", isDirectory: false))

let iconFiles: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, size) in iconFiles {
    try savePNG(try makeBitmap(size: size, draw: drawAppIcon), to: iconsetDir.appendingPathComponent(name, isDirectory: false))
}

try savePNG(try makeBitmap(size: 18, draw: drawMenuBarIcon), to: assetsDir.appendingPathComponent("MenuBarTemplate.png", isDirectory: false))
try savePNG(try makeBitmap(size: 36, draw: drawMenuBarIcon), to: assetsDir.appendingPathComponent("MenuBarTemplate@2x.png", isDirectory: false))
try savePNG(try makeBitmap(size: 18, draw: drawAppIcon), to: assetsDir.appendingPathComponent("MenuBarLogo.png", isDirectory: false))
try savePNG(try makeBitmap(size: 36, draw: drawAppIcon), to: assetsDir.appendingPathComponent("MenuBarLogo@2x.png", isDirectory: false))

print("Generated icon assets in \(assetsDir.path)")
