#!/usr/bin/env swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assetsDir = root.appendingPathComponent("Assets", isDirectory: true)
let output = assetsDir.appendingPathComponent("agentconsole-dmg-background.tiff", isDirectory: false)
let iconURL = assetsDir.appendingPathComponent("AppIcon-1024.png", isDirectory: false)

let pointWidth = 660
let pointHeight = 400
let scale = 2
let width = pointWidth * scale
let height = pointHeight * scale

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Could not create DMG background bitmap")
}

bitmap.size = NSSize(width: pointWidth, height: pointHeight)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high

let rect = CGRect(x: 0, y: 0, width: pointWidth, height: pointHeight)
NSColor(calibratedRed: 0.945, green: 0.965, blue: 0.972, alpha: 1).setFill()
NSBezierPath(rect: rect).fill()

let lineColor = NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.17, alpha: 0.96)
lineColor.setStroke()
let arrow = NSBezierPath()
arrow.lineWidth = 7
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: CGPoint(x: 325, y: 236))
arrow.line(to: CGPoint(x: 338, y: 219))
arrow.line(to: CGPoint(x: 325, y: 202))
arrow.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let tiff = bitmap.representation(using: .tiff, properties: [:]) else {
    fatalError("Could not encode DMG background")
}

try tiff.write(to: output)
print("Generated DMG background at \(output.path)")
