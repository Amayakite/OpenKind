import AppKit
import Foundation

let destination = CommandLine.arguments[1]
let fm = FileManager.default
try fm.createDirectory(atPath: destination, withIntermediateDirectories: true)
func draw(_ pixels: Int, filename: String) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 220, yRadius: 220)
    NSGradient(starting: NSColor(calibratedRed: 0.18, green: 0.26, blue: 0.70, alpha: 1), ending: NSColor(calibratedRed: 0.39, green: 0.58, blue: 1, alpha: 1))!.draw(in: background, angle: 65)
    func rounded(_ rect: NSRect, radius: CGFloat, color: NSColor) { color.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill() }
    rounded(NSRect(x: 285, y: 352, width: 420, height: 365), radius: 58, color: NSColor.white.withAlphaComponent(0.26))
    rounded(NSRect(x: 245, y: 288, width: 420, height: 365), radius: 58, color: NSColor.white.withAlphaComponent(0.50))
    rounded(NSRect(x: 205, y: 224, width: 420, height: 365), radius: 58, color: .white)
    let blue = NSColor(calibratedRed: 0.28, green: 0.39, blue: 0.83, alpha: 1)
    rounded(NSRect(x: 270, y: 484, width: 230, height: 22), radius: 11, color: blue.withAlphaComponent(0.75))
    rounded(NSRect(x: 270, y: 421, width: 165, height: 22), radius: 11, color: blue.withAlphaComponent(0.40))
    let circle = NSBezierPath(ovalIn: NSRect(x: 518, y: 187, width: 286, height: 286))
    blue.setFill(); circle.fill()
    let arrow = NSBezierPath()
    arrow.lineWidth = 34; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 600, y: 281)); arrow.line(to: NSPoint(x: 716, y: 397))
    arrow.move(to: NSPoint(x: 625, y: 397)); arrow.line(to: NSPoint(x: 716, y: 397)); arrow.line(to: NSPoint(x: 716, y: 306))
    NSColor.white.setStroke(); arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG") }
    try png.write(to: URL(fileURLWithPath: destination).appendingPathComponent(filename))
}
for (pixels, name) in [(16,"icon_16x16.png"), (32,"icon_16x16@2x.png"), (32,"icon_32x32.png"), (64,"icon_32x32@2x.png"), (128,"icon_128x128.png"), (256,"icon_128x128@2x.png"), (256,"icon_256x256.png"), (512,"icon_256x256@2x.png"), (512,"icon_512x512.png"), (1024,"icon_512x512@2x.png")] { try draw(pixels, filename: name) }
