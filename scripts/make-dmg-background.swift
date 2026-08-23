#!/usr/bin/env swift
//
// Zeichnet Resources/dmg-background.png, den Hintergrund des Disk-Images.
// Aufruf: swift scripts/make-dmg-background.swift
//
// Das Bild trägt die Anleitung: links steht die App, rechts der Ordner, dazwischen
// ein Pfeil. Wer das Fenster öffnet, weiss ohne Textdatei, was zu tun ist.

import AppKit
import Foundation

// Fenstermass des DMG. Die Icons setzt das Skript make-dmg.sh an dieselben Stellen.
let width = 660.0
let height = 420.0
let scale = 2.0

let context = CGContext(
    data: nil,
    width: Int(width * scale),
    height: Int(height * scale),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
context.scaleBy(x: scale, y: scale)

func rgb(_ hex: UInt32, _ alpha: Double = 1) -> CGColor {
    CGColor(
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// Grund: dasselbe Nachtblau wie im App-Icon, damit Fenster und Icon zusammengehören.
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [rgb(0x1B2740), rgb(0x0F1626)] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: height),
    end: CGPoint(x: width, y: 0),
    options: []
)

// Weicher Lichtschein hinter der Bildmitte, Anklang an das Icon.
let glow = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [rgb(0x7DB7FF, 0.16), rgb(0x7DB7FF, 0)] as CFArray,
    locations: [0, 1]
)!
context.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: width / 2, y: height * 0.58),
    startRadius: 0,
    endCenter: CGPoint(x: width / 2, y: height * 0.58),
    endRadius: 300,
    options: []
)

// Pfeil zwischen den beiden Icon-Positionen (bei y = 232 im Finder-Koordinatensystem).
let arrowY = height - 232.0
let arrowStart = 258.0
let arrowEnd = 402.0
let shaftHeight = 10.0
let headWidth = 34.0

context.setFillColor(rgb(0x9FC4F5, 0.85))
context.beginPath()
context.move(to: CGPoint(x: arrowStart, y: arrowY - shaftHeight / 2))
context.addLine(to: CGPoint(x: arrowEnd - headWidth, y: arrowY - shaftHeight / 2))
context.addLine(to: CGPoint(x: arrowEnd - headWidth, y: arrowY - 20))
context.addLine(to: CGPoint(x: arrowEnd, y: arrowY))
context.addLine(to: CGPoint(x: arrowEnd - headWidth, y: arrowY + 20))
context.addLine(to: CGPoint(x: arrowEnd - headWidth, y: arrowY + shaftHeight / 2))
context.addLine(to: CGPoint(x: arrowStart, y: arrowY + shaftHeight / 2))
context.closePath()
context.fillPath()

// Beschriftungen
func draw(_ text: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight,
          color: NSColor, centered: Bool = true) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let bounds = string.size()
    let origin = centered
        ? NSPoint(x: point.x - bounds.width / 2, y: point.y)
        : NSPoint(x: point.x, y: point.y)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    string.draw(at: origin)
    NSGraphicsContext.restoreGraphicsState()
}

draw("Drag Lumina into Applications",
     at: CGPoint(x: width / 2, y: height - 96), size: 19, weight: .medium,
     color: NSColor(white: 1, alpha: 0.92))

// Der Hinweis auf die Gatekeeper-Meldung gehört genau hierhin: er wird gebraucht,
// bevor jemand die Textdatei öffnet.
draw("First launch is blocked by macOS. Open System Settings, Privacy & Security,",
     at: CGPoint(x: width / 2, y: 58), size: 12, weight: .regular,
     color: NSColor(white: 1, alpha: 0.5))
draw("scroll to Security and click Open Anyway. Details in Read me first.txt",
     at: CGPoint(x: width / 2, y: 38), size: 12, weight: .regular,
     color: NSColor(white: 1, alpha: 0.5))

let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
rep.size = NSSize(width: width, height: height)
let out = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Resources/dmg-background.png")
try rep.representation(using: .png, properties: [:])!.write(to: out)
print("Resources/dmg-background.png geschrieben (\(Int(width))x\(Int(height)) @\(Int(scale))x)")
