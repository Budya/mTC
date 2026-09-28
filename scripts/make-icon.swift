// Рисует иконку приложения (дискета) и раскладывает PNG по AppIcon.appiconset.
// Использование: swift scripts/make-icon.swift
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconSet = root.appendingPathComponent("mTC/Assets.xcassets/AppIcon.appiconset")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fillGradient(_ ctx: CGContext, _ path: CGPath, _ top: CGColor, _ bottom: CGColor, _ rect: CGRect) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    ctx.restoreGState()
}

/// Рисует иконку на холсте 1024×1024 (сетка иконок macOS: содержимое 824×824 с полями 100).
func drawIcon(_ ctx: CGContext) {
    let minX: CGFloat = 100, minY: CGFloat = 100, maxX: CGFloat = 924, maxY: CGFloat = 924
    let r: CGFloat = 72, notch: CGFloat = 96

    // Корпус со срезанным правым верхним углом.
    let body = CGMutablePath()
    body.move(to: CGPoint(x: minX + r, y: minY))
    body.addArc(tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX, y: minY + r), radius: r)
    body.addLine(to: CGPoint(x: maxX, y: maxY - notch))
    body.addLine(to: CGPoint(x: maxX - notch, y: maxY))
    body.addArc(tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX, y: maxY - r), radius: r)
    body.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX + r, y: minY), radius: r)
    body.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(body)
    ctx.setFillColor(color(0x2A56C6))
    ctx.fillPath()
    ctx.restoreGState()
    fillGradient(ctx, body, color(0x3D6FE0), color(0x1E3F9E), CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))

    // Металлическая шторка сверху с прорезью.
    let shutterRect = CGRect(x: 292, y: 610, width: 440, height: 314)
    let shutter = CGMutablePath()
    shutter.addRect(shutterRect)
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    fillGradient(ctx, shutter, color(0xF1F4F8), color(0xA9B3C1), shutterRect)
    ctx.restoreGState()
    ctx.addPath(roundedRect(CGRect(x: 570, y: 660, width: 100, height: 214), 14))
    ctx.setFillColor(color(0x1B2433))
    ctx.fillPath()

    // Этикетка: цветная полоса и две колонки строк — намёк на две панели.
    let labelRect = CGRect(x: 196, y: 150, width: 632, height: 380)
    let label = roundedRect(labelRect, 30)
    fillGradient(ctx, label, color(0xFFFFFF), color(0xE7EBF2), labelRect)

    ctx.saveGState()
    ctx.addPath(label)
    ctx.clip()
    ctx.setFillColor(color(0xF2A93B))
    ctx.fill(CGRect(x: labelRect.minX, y: labelRect.maxY - 64, width: labelRect.width, height: 64))
    ctx.restoreGState()

    ctx.setFillColor(color(0xB9C4D8))
    ctx.fill(CGRect(x: 508, y: 186, width: 8, height: 262))

    ctx.setFillColor(color(0x8FA3C9))
    for (index, y) in [404, 344, 284, 224].enumerated() {
        let leftWidth: CGFloat = index % 2 == 0 ? 236 : 180
        let rightWidth: CGFloat = index % 2 == 0 ? 170 : 236
        ctx.addPath(roundedRect(CGRect(x: 240, y: CGFloat(y), width: leftWidth, height: 26), 13))
        ctx.addPath(roundedRect(CGRect(x: 548, y: CGFloat(y), width: rightWidth, height: 26), 13))
    }
    ctx.fillPath()
}

func renderPNG(pixels: Int, to url: URL) throws {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(ctx)

    let image = ctx.makeImage()!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try renderPNG(pixels: pixels, to: iconSet.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: iconSet.appendingPathComponent("Contents.json"))

let catalogInfo = try JSONSerialization.data(withJSONObject: ["info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys])
try catalogInfo.write(to: iconSet.deletingLastPathComponent().appendingPathComponent("Contents.json"))

print("Иконка записана в \(iconSet.path)")
