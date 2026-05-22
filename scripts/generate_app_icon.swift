import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]

for size in sizes {
    guard let rep = NSBitmapImageRep(
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
        fatalError("failed to allocate icon bitmap \(size)")
    }

    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor(red: 0.06, green: 0.11, blue: 0.16, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: CGFloat(size) * 0.22, yRadius: CGFloat(size) * 0.22).fill()

    let inset = CGFloat(size) * 0.15
    let window = NSRect(x: inset, y: CGFloat(size) * 0.28, width: CGFloat(size) - inset * 2, height: CGFloat(size) * 0.48)
    NSColor(red: 0.88, green: 0.95, blue: 1.0, alpha: 1).setFill()
    NSBezierPath(roundedRect: window, xRadius: CGFloat(size) * 0.07, yRadius: CGFloat(size) * 0.07).fill()

    NSColor(red: 0.20, green: 0.62, blue: 0.86, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: window.minX, y: window.maxY - CGFloat(size) * 0.10, width: window.width, height: CGFloat(size) * 0.10)).fill()

    NSColor(red: 0.05, green: 0.09, blue: 0.13, alpha: 1).setStroke()
    let lens = NSBezierPath(ovalIn: NSRect(
        x: CGFloat(size) * 0.37,
        y: CGFloat(size) * 0.38,
        width: CGFloat(size) * 0.26,
        height: CGFloat(size) * 0.26
    ))
    lens.lineWidth = max(2, CGFloat(size) * 0.045)
    lens.stroke()

    NSColor(red: 0.19, green: 0.78, blue: 0.56, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(
        x: CGFloat(size) * 0.68,
        y: CGFloat(size) * 0.19,
        width: CGFloat(size) * 0.16,
        height: CGFloat(size) * 0.16
    )).fill()

    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("failed to render icon size \(size)")
    }

    try data.write(to: output.appendingPathComponent("appshot-\(size).png"))
}
