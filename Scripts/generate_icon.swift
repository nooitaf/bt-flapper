#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

let canvasSize: CGFloat = 1024
let iconInset: CGFloat = 100
let iconRect = CGRect(
    x: iconInset,
    y: iconInset,
    width: canvasSize - iconInset * 2,
    height: canvasSize - iconInset * 2
)
let cornerRadius: CGFloat = iconRect.width * 0.2237

func makeContinuousRoundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    // Smooth squircle-like rounded rect matching macOS app icon geometry
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).cgPath
}

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &points) {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo, .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }
        return path
    }
}

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
        data: nil,
        width: Int(canvasSize),
        height: Int(canvasSize),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else {
    fputs("Failed to create CGContext\n", stderr)
    exit(1)
}

ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)

let squirclePath = makeContinuousRoundedRectPath(iconRect, radius: cornerRadius)

// 1. Outer macOS icon drop shadow
ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -14),
    blur: 28,
    color: CGColor(red: 0, green: 0.04, blue: 0.16, alpha: 0.34)
)
ctx.addPath(squirclePath)
ctx.setFillColor(CGColor(red: 0.04, green: 0.28, blue: 0.95, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

// 2. Clipped squircle background gradient + radial top-left sheen
ctx.saveGState()
ctx.addPath(squirclePath)
ctx.clip()

let bgColors = [
    CGColor(red: 0.03, green: 0.23, blue: 0.88, alpha: 1.0), // Deep Bluetooth royal blue (bottom)
    CGColor(red: 0.07, green: 0.48, blue: 0.99, alpha: 1.0), // Vibrant macOS blue (mid)
    CGColor(red: 0.22, green: 0.72, blue: 1.00, alpha: 1.0)  // Bright sky cyan (top)
] as CFArray
if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.55, 1.0]) {
    ctx.drawLinearGradient(
        bgGradient,
        start: CGPoint(x: canvasSize * 0.5, y: iconRect.minY),
        end: CGPoint(x: canvasSize * 0.5, y: iconRect.maxY),
        options: []
    )
}

// Soft top-left radial highlight for Apple-like depth
let glowColors = [
    CGColor(red: 0.75, green: 0.93, blue: 1.0, alpha: 0.36),
    CGColor(red: 0.75, green: 0.93, blue: 1.0, alpha: 0.0)
] as CFArray
if let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: iconRect.minX + iconRect.width * 0.28, y: iconRect.maxY - iconRect.height * 0.12),
        startRadius: 0,
        endCenter: CGPoint(x: iconRect.minX + iconRect.width * 0.35, y: iconRect.maxY - iconRect.height * 0.2),
        endRadius: iconRect.width * 0.65,
        options: [.drawsBeforeStartLocation]
    )
}

// Subtle inner rim highlight
ctx.addPath(squirclePath)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.24))
ctx.setLineWidth(6)
ctx.strokePath()
ctx.restoreGState()

// 3. Foreground symbol: minimalist MacBook + Bluetooth rune + signal waves
ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -10),
    blur: 20,
    color: CGColor(red: 0.0, green: 0.10, blue: 0.38, alpha: 0.35)
)

let centerX = canvasSize / 2.0

// Laptop screen frame
let screenW: CGFloat = 456
let screenH: CGFloat = 304
let screenX = centerX - screenW / 2.0
let screenY: CGFloat = 354
let screenRect = CGRect(x: screenX, y: screenY, width: screenW, height: screenH)
let screenPath = makeContinuousRoundedRectPath(screenRect, radius: 34)

// Translucent glass fill inside screen
ctx.saveGState()
ctx.addPath(screenPath)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
ctx.fillPath()
ctx.restoreGState()

// Crisp white screen bezel
ctx.addPath(screenPath)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
ctx.setLineWidth(28)
ctx.strokePath()

// Laptop base / hinge lip
let baseW: CGFloat = 588
let baseH: CGFloat = 40
let baseRect = CGRect(x: centerX - baseW / 2.0, y: screenY - baseH - 18, width: baseW, height: baseH)
let basePath = CGMutablePath()
let topR: CGFloat = 10
let botR: CGFloat = 20
basePath.move(to: CGPoint(x: baseRect.minX + topR, y: baseRect.maxY))
basePath.addLine(to: CGPoint(x: baseRect.maxX - topR, y: baseRect.maxY))
basePath.addQuadCurve(to: CGPoint(x: baseRect.maxX, y: baseRect.maxY - topR), control: CGPoint(x: baseRect.maxX, y: baseRect.maxY))
basePath.addLine(to: CGPoint(x: baseRect.maxX, y: baseRect.minY + botR))
basePath.addQuadCurve(to: CGPoint(x: baseRect.maxX - botR, y: baseRect.minY), control: CGPoint(x: baseRect.maxX, y: baseRect.minY))
basePath.addLine(to: CGPoint(x: baseRect.minX + botR, y: baseRect.minY))
basePath.addQuadCurve(to: CGPoint(x: baseRect.minX, y: baseRect.minY + botR), control: CGPoint(x: baseRect.minX, y: baseRect.minY))
basePath.addLine(to: CGPoint(x: baseRect.minX, y: baseRect.maxY - topR))
basePath.addQuadCurve(to: CGPoint(x: baseRect.minX + topR, y: baseRect.maxY), control: CGPoint(x: baseRect.minX, y: baseRect.maxY))
basePath.closeSubpath()

ctx.addPath(basePath)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
ctx.fillPath()

// Subtle thumb notch on base
let notchW: CGFloat = 96
let notchH: CGFloat = 12
let notchRect = CGRect(x: centerX - notchW / 2.0, y: baseRect.maxY - notchH, width: notchW, height: notchH)
let notchPath = makeContinuousRoundedRectPath(notchRect, radius: 6)
ctx.addPath(notchPath)
ctx.setFillColor(CGColor(red: 0.08, green: 0.42, blue: 0.96, alpha: 0.55))
ctx.fillPath()

// Crisp Bluetooth rune centered inside the screen
let btCenterY = screenRect.midY
let btHalfH: CGFloat = 86
let btRightX = centerX + 54
let btLeftX = centerX - 48
let btMidOffset: CGFloat = 43

let btPath = CGMutablePath()
// Top-left tail -> center -> bottom-right -> bottom -> top -> top-right -> center -> bottom-left tail
btPath.move(to: CGPoint(x: btLeftX, y: btCenterY + btMidOffset))
btPath.addLine(to: CGPoint(x: btRightX, y: btCenterY - btMidOffset))
btPath.addLine(to: CGPoint(x: centerX, y: btCenterY - btHalfH))
btPath.addLine(to: CGPoint(x: centerX, y: btCenterY + btHalfH))
btPath.addLine(to: CGPoint(x: btRightX, y: btCenterY + btMidOffset))
btPath.addLine(to: CGPoint(x: btLeftX, y: btCenterY - btMidOffset))

ctx.addPath(btPath)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
ctx.setLineWidth(24)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.strokePath()

// Two gentle wireless arcs radiating above the lid
let arcCenter = CGPoint(x: centerX, y: screenRect.maxY - 24)
let startAngle = CGFloat.pi * 0.27
let endAngle = CGFloat.pi * 0.73

let innerArc = CGMutablePath()
innerArc.addArc(center: arcCenter, radius: 112, startAngle: startAngle, endAngle: endAngle, clockwise: false)
ctx.addPath(innerArc)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.88))
ctx.setLineWidth(22)
ctx.setLineCap(.round)
ctx.strokePath()

let outerArc = CGMutablePath()
outerArc.addArc(center: arcCenter, radius: 168, startAngle: startAngle + 0.04, endAngle: endAngle - 0.04, clockwise: false)
ctx.addPath(outerArc)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.56))
ctx.setLineWidth(22)
ctx.setLineCap(.round)
ctx.strokePath()

ctx.restoreGState()

// Save PNG
guard let cgImage = ctx.makeImage() else {
    fputs("Failed to make CGImage\n", stderr)
    exit(1)
}
let rep = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.png"
let outputURL = URL(fileURLWithPath: outputPath)
try pngData.write(to: outputURL)
print("Generated \(outputURL.path)")
