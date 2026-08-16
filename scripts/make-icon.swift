#!/usr/bin/env swift
//
// Erzeugt Resources/AppIcon.icns.
// Aufruf: swift scripts/make-icon.swift
//
// Gezeichnet wird ein Stapel aus drei Fotokarten vor einem warmen Verlauf -
// bewusst ohne SF Symbols, damit das Icon frei verwendbar bleibt.

import AppKit
import CoreGraphics
import Foundation

let size = 1024
let radius: CGFloat = 224 // macOS-Squircle-Anmutung

guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("CGContext konnte nicht erstellt werden")
}

let full = CGRect(x: 0, y: 0, width: size, height: size)

// Hintergrund: abgerundetes Quadrat mit Verlauf von Tiefblau nach Violett.
let backgroundPath = CGPath(roundedRect: full, cornerWidth: radius, cornerHeight: radius, transform: nil)
context.saveGState()
context.addPath(backgroundPath)
context.clip()

let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [
        CGColor(red: 0.13, green: 0.16, blue: 0.42, alpha: 1),
        CGColor(red: 0.42, green: 0.20, blue: 0.58, alpha: 1),
        CGColor(red: 0.86, green: 0.44, blue: 0.38, alpha: 1),
    ] as CFArray,
    locations: [0.0, 0.55, 1.0]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size, y: 0),
    options: []
)

/// Eine leicht gedrehte Fotokarte.
func drawCard(rect: CGRect, rotation: CGFloat, fill: CGColor, alpha: CGFloat) {
    context.saveGState()
    context.translateBy(x: rect.midX, y: rect.midY)
    context.rotate(by: rotation)
    context.translateBy(x: -rect.width / 2, y: -rect.height / 2)

    let card = CGRect(x: 0, y: 0, width: rect.width, height: rect.height)
    let path = CGPath(roundedRect: card, cornerWidth: 34, cornerHeight: 34, transform: nil)

    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: CGColor(gray: 0, alpha: 0.35))
    context.setAlpha(alpha)
    context.addPath(path)
    context.setFillColor(fill)
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0, color: nil)
    context.restoreGState()
}

let cardSize = CGSize(width: 520, height: 400)
let center = CGRect(
    x: (CGFloat(size) - cardSize.width) / 2,
    y: (CGFloat(size) - cardSize.height) / 2,
    width: cardSize.width,
    height: cardSize.height
)

// Zwei Karten im Hintergrund deuten den Stapel an.
drawCard(rect: center.offsetBy(dx: -46, dy: 62), rotation: 0.14, fill: CGColor(gray: 1, alpha: 1), alpha: 0.45)
drawCard(rect: center.offsetBy(dx: 40, dy: 30), rotation: -0.07, fill: CGColor(gray: 1, alpha: 1), alpha: 0.7)

// Vordere Karte mit einer kleinen Landschaft: Sonne und zwei Berge.
context.saveGState()
let front = center.offsetBy(dx: 0, dy: -26)
let frontPath = CGPath(roundedRect: front, cornerWidth: 34, cornerHeight: 34, transform: nil)
context.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: CGColor(gray: 0, alpha: 0.45))
context.addPath(frontPath)
context.setFillColor(CGColor(red: 0.99, green: 0.98, blue: 0.96, alpha: 1))
context.fillPath()
context.setShadow(offset: .zero, blur: 0, color: nil)

context.addPath(frontPath)
context.clip()

// Himmel
context.setFillColor(CGColor(red: 0.90, green: 0.94, blue: 0.99, alpha: 1))
context.fill(front)

// Sonne
context.setFillColor(CGColor(red: 0.98, green: 0.76, blue: 0.28, alpha: 1))
context.fillEllipse(in: CGRect(x: front.minX + 96, y: front.maxY - 140, width: 84, height: 84))

// Hinterer Berg
context.setFillColor(CGColor(red: 0.45, green: 0.55, blue: 0.72, alpha: 1))
context.beginPath()
context.move(to: CGPoint(x: front.minX, y: front.minY + 110))
context.addLine(to: CGPoint(x: front.minX + 200, y: front.minY + 290))
context.addLine(to: CGPoint(x: front.minX + 380, y: front.minY + 110))
context.closePath()
context.fillPath()

// Vorderer Berg
context.setFillColor(CGColor(red: 0.24, green: 0.36, blue: 0.55, alpha: 1))
context.beginPath()
context.move(to: CGPoint(x: front.minX + 150, y: front.minY))
context.addLine(to: CGPoint(x: front.minX + 340, y: front.minY + 230))
context.addLine(to: CGPoint(x: front.maxX, y: front.minY))
context.closePath()
context.fillPath()

// Wiese
context.setFillColor(CGColor(red: 0.19, green: 0.30, blue: 0.44, alpha: 1))
context.fill(CGRect(x: front.minX, y: front.minY, width: front.width, height: 60))
context.restoreGState()

context.restoreGState()

guard let image = context.makeImage() else { fatalError("Bild konnte nicht gerendert werden") }

// Iconset schreiben und mit iconutil in .icns wandeln.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, pixels) in variants {
    let rep = NSBitmapImageRep(
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
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSImage(cgImage: image, size: NSSize(width: pixels, height: pixels))
        .draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: iconset.appendingPathComponent("\(name).png"))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    fatalError("iconutil ist fehlgeschlagen")
}
print("Resources/AppIcon.icns geschrieben")
