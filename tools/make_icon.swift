#!/usr/bin/env swift
// Render a 1024×1024 PNG for the macOS app icon.
// Usage: swift tools/make_icon.swift <output.png>

import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make_icon.swift <output.png>\n".utf8))
    exit(2)
}
let outPath = CommandLine.arguments[1]
let outURL  = URL(fileURLWithPath: outPath)

let size: CGFloat = 1024
// macOS Big Sur+ squircle: ~22.4% of side. Apple uses a true superellipse,
// but a plain rounded rect with this radius is visually indistinguishable.
let cornerRadius: CGFloat = 230

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 32
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let cs  = CGColorSpaceCreateDeviceRGB()

// MARK: Background — soft warm gradient inside the squircle
let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                    cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
ctx.saveGState()
ctx.addPath(bgPath); ctx.clip()

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    NSColor(calibratedRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a).cgColor
}

let bgGrad = CGGradient(
    colorsSpace: cs,
    colors: [rgb(0xFB, 0xF7, 0xEF), rgb(0xEF, 0xE2, 0xCD)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(bgGrad,
                       start: CGPoint(x: 0, y: size),
                       end:   CGPoint(x: size, y: 0),
                       options: [])

// Top-left highlight glow (liquid-glass feel)
let glowGrad = CGGradient(
    colorsSpace: cs,
    colors: [rgb(0xFF, 0xFF, 0xFF, 0.55), rgb(0xFF, 0xFF, 0xFF, 0)] as CFArray,
    locations: [0, 1]
)!
ctx.drawRadialGradient(glowGrad,
                       startCenter: CGPoint(x: size * 0.28, y: size * 0.82),
                       startRadius: 0,
                       endCenter:   CGPoint(x: size * 0.28, y: size * 0.82),
                       endRadius:   size * 0.6,
                       options: [])

ctx.restoreGState()

// MARK: Bars — three ascending bars matching the menu-bar glyph
let bars: [(heightFrac: CGFloat, color: CGColor)] = [
    (0.34, rgb(0x5B, 0x8D, 0xEF)), // input blue
    (0.55, rgb(0xB5, 0x8B, 0xE0)), // cache-write purple
    (0.74, rgb(0xC9, 0x64, 0x42)), // accent orange (tallest)
]
let barWidth: CGFloat = 150
let gap: CGFloat = 70
let totalWidth = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * gap
let baseY: CGFloat = size * 0.22
let originX: CGFloat = (size - totalWidth) / 2

for (i, b) in bars.enumerated() {
    let x = originX + CGFloat(i) * (barWidth + gap)
    let h = (size * 0.62) * b.heightFrac + 60   // min height + scaled
    let rect = CGRect(x: x, y: baseY, width: barWidth, height: h)
    // Soft shadow under bar
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8),
                  blur: 24,
                  color: rgb(0x1A, 0x16, 0x25, 0.18))
    let path = CGPath(roundedRect: rect, cornerWidth: 28, cornerHeight: 28, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(b.color)
    ctx.fillPath()
    ctx.restoreGState()

    // Subtle top highlight on each bar
    let topRect = CGRect(x: x + 14, y: baseY + h - 28, width: barWidth - 28, height: 10)
    let topPath = CGPath(roundedRect: topRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
    ctx.addPath(topPath)
    ctx.setFillColor(rgb(0xFF, 0xFF, 0xFF, 0.35))
    ctx.fillPath()
}

// MARK: Inner border (1px hairline) for crisp edge on light backgrounds
ctx.saveGState()
ctx.addPath(bgPath)
ctx.setStrokeColor(rgb(0x1A, 0x16, 0x25, 0.10))
ctx.setLineWidth(2)
ctx.strokePath()
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()

// Persist
guard let data = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("PNG encode failed\n".utf8))
    exit(1)
}
do {
    try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try data.write(to: outURL)
    print("✓ wrote \(outURL.path) (\(data.count / 1024) KB)")
} catch {
    FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
    exit(1)
}
