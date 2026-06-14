#!/usr/bin/env swift
import AppKit
import Foundation

struct IconVariant {
    let filename: String
    let pixels: Int
}

let variants = [
    IconVariant(filename: "icon_16x16.png", pixels: 16),
    IconVariant(filename: "icon_16x16@2x.png", pixels: 32),
    IconVariant(filename: "icon_32x32.png", pixels: 32),
    IconVariant(filename: "icon_32x32@2x.png", pixels: 64),
    IconVariant(filename: "icon_128x128.png", pixels: 128),
    IconVariant(filename: "icon_128x128@2x.png", pixels: 256),
    IconVariant(filename: "icon_256x256.png", pixels: 256),
    IconVariant(filename: "icon_256x256@2x.png", pixels: 512),
    IconVariant(filename: "icon_512x512.png", pixels: 512),
    IconVariant(filename: "icon_512x512@2x.png", pixels: 1024)
]

guard CommandLine.arguments.count == 3 else {
    fputs("usage: generate_app_icon.swift <output.iconset> <menu-bar-template.png>\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let menuBarURL = URL(fileURLWithPath: CommandLine.arguments[2])
let fileManager = FileManager.default
try? fileManager.removeItem(at: outputURL)
try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

for variant in variants {
    let image = drawIcon(pixels: variant.pixels)
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        fputs("failed to render \(variant.filename)\n", stderr)
        exit(1)
    }
    try png.write(to: outputURL.appendingPathComponent(variant.filename))
}

let menuBarImage = drawMenuBarIcon(pixels: 36)
guard
    let menuTiff = menuBarImage.tiffRepresentation,
    let menuBitmap = NSBitmapImageRep(data: menuTiff),
    let menuPNG = menuBitmap.representation(using: .png, properties: [:])
else {
    fputs("failed to render menu bar icon\n", stderr)
    exit(1)
}
try menuPNG.write(to: menuBarURL)

private func drawIcon(pixels: Int) -> NSImage {
    let size = NSSize(width: pixels, height: pixels)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(origin: .zero, size: size)
    NSColor.clear.setFill()
    rect.fill()

    let scale = CGFloat(pixels) / 1024.0
    func s(_ value: CGFloat) -> CGFloat { value * scale }

    let iconRect = rect.insetBy(dx: s(64), dy: s(64))
    let radius = s(220)
    let basePath = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.08, green: 0.39, blue: 0.98, alpha: 1),
        NSColor(calibratedRed: 0.00, green: 0.68, blue: 0.64, alpha: 1)
    ])
    gradient?.draw(in: basePath, angle: 135)

    NSColor(calibratedWhite: 1, alpha: 0.20).setStroke()
    basePath.lineWidth = max(1, s(18))
    basePath.stroke()

    let glowPath = NSBezierPath(ovalIn: NSRect(x: s(610), y: s(620), width: s(300), height: s(260)))
    NSColor(calibratedRed: 1.0, green: 0.94, blue: 0.58, alpha: 0.22).setFill()
    glowPath.fill()

    let bubbleRect = NSRect(x: s(176), y: s(192), width: s(672), height: s(640))
    let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: s(158), yRadius: s(158))
    NSColor(calibratedWhite: 1, alpha: 0.92).setFill()
    bubble.fill()

    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: s(340), y: s(196)))
    tail.line(to: NSPoint(x: s(282), y: s(98)))
    tail.line(to: NSPoint(x: s(450), y: s(178)))
    tail.close()
    NSColor(calibratedWhite: 1, alpha: 0.92).setFill()
    tail.fill()

    let titleFont = NSFont.systemFont(ofSize: s(384), weight: .bold)
    let titleStyle = NSMutableParagraphStyle()
    titleStyle.alignment = .center
    let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: NSColor(calibratedRed: 0.05, green: 0.22, blue: 0.62, alpha: 1),
        .paragraphStyle: titleStyle
    ]
    let titleRect = NSRect(x: s(160), y: s(330), width: s(420), height: s(390))
    NSString(string: "G").draw(in: titleRect, withAttributes: titleAttributes)

    let arrow = NSBezierPath()
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: s(548), y: s(548)))
    arrow.line(to: NSPoint(x: s(720), y: s(548)))
    arrow.line(to: NSPoint(x: s(666), y: s(602)))
    arrow.move(to: NSPoint(x: s(720), y: s(548)))
    arrow.line(to: NSPoint(x: s(666), y: s(494)))
    NSColor(calibratedRed: 0.02, green: 0.55, blue: 0.52, alpha: 1).setStroke()
    arrow.lineWidth = max(2, s(42))
    arrow.stroke()

    let smallFont = NSFont.systemFont(ofSize: s(162), weight: .semibold)
    let smallAttributes: [NSAttributedString.Key: Any] = [
        .font: smallFont,
        .foregroundColor: NSColor(calibratedRed: 0.02, green: 0.55, blue: 0.52, alpha: 1),
        .paragraphStyle: titleStyle
    ]
    NSString(string: "A").draw(in: NSRect(x: s(574), y: s(330), width: s(210), height: s(170)), withAttributes: smallAttributes)

    return image
}

private func drawMenuBarIcon(pixels: Int) -> NSImage {
    let size = NSSize(width: pixels, height: pixels)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    let scale = CGFloat(pixels) / 36.0
    func s(_ value: CGFloat) -> CGFloat { value * scale }

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()
    NSColor.black.setStroke()
    NSColor.black.setFill()

    let bubble = NSBezierPath(roundedRect: NSRect(x: s(4), y: s(7), width: s(28), height: s(22)), xRadius: s(7), yRadius: s(7))
    bubble.lineWidth = max(1, s(2))
    bubble.stroke()

    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: s(12), y: s(8)))
    tail.line(to: NSPoint(x: s(8), y: s(3)))
    tail.line(to: NSPoint(x: s(17), y: s(7)))
    tail.lineWidth = max(1, s(2))
    tail.stroke()

    let textStyle = NSMutableParagraphStyle()
    textStyle.alignment = .center
    let textAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: s(17), weight: .bold),
        .foregroundColor: NSColor.black,
        .paragraphStyle: textStyle
    ]
    NSString(string: "G").draw(in: NSRect(x: s(5), y: s(9), width: s(15), height: s(18)), withAttributes: textAttributes)

    let arrow = NSBezierPath()
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: s(19), y: s(18)))
    arrow.line(to: NSPoint(x: s(28), y: s(18)))
    arrow.line(to: NSPoint(x: s(25), y: s(21)))
    arrow.move(to: NSPoint(x: s(28), y: s(18)))
    arrow.line(to: NSPoint(x: s(25), y: s(15)))
    arrow.lineWidth = max(1.5, s(2.6))
    arrow.stroke()

    return image
}
