#!/usr/bin/env swift
//
// Erzeugt Resources/AppIcon.icns aus Resources/AppIcon.svg.
// Aufruf: swift scripts/make-icon.swift
//
// Die SVG ist die Quelle; sie wird für jede Grösse einzeln gerastert, statt
// eine grosse Bitmap herunterzuskalieren. Das hält die kleinen Grössen so
// scharf, wie es das Motiv zulässt.

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("Resources/AppIcon.svg")

guard let artwork = NSImage(contentsOf: source) else {
    FileHandle.standardError.write(Data("AppIcon.svg nicht lesbar: \(source.path)\n".utf8))
    exit(1)
}

/// Rastert die Vorlage in genau der gewünschten Kantenlänge.
func render(_ pixels: Int) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
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
    ) else { return nil }

    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    artwork.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

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
    guard let rep = render(pixels), let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("Konnte \(name) nicht rendern\n".utf8))
        exit(1)
    }
    try png.write(to: iconset.appendingPathComponent("\(name).png"))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil ist fehlgeschlagen\n".utf8))
    exit(1)
}
print("Resources/AppIcon.icns aus AppIcon.svg erzeugt (\(variants.count) Grössen)")
