import AppKit

enum MenuBarIcon {
    /// Renders a crisp template menu bar icon matching the bt-flapper laptop + Bluetooth logo.
    /// When disabled, overlays a macOS-style diagonal slash with a transparent cutout.
    static func image(enabled: Bool) -> NSImage {
        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setFillColor(NSColor.black.cgColor)

            let centerX: CGFloat = 10.0

            // Laptop screen frame
            let screenRect = CGRect(x: 3.5, y: 4.2, width: 13.0, height: 9.4)
            let screenPath = NSBezierPath(roundedRect: screenRect, xRadius: 1.7, yRadius: 1.7)
            screenPath.lineWidth = 1.45
            screenPath.stroke()

            // Laptop base bar
            let baseRect = CGRect(x: 1.5, y: 1.8, width: 17.0, height: 1.5)
            let basePath = NSBezierPath(roundedRect: baseRect, xRadius: 0.75, yRadius: 0.75)
            basePath.fill()

            // Crisp Bluetooth rune inside the screen
            let btCenterY = screenRect.midY
            let btHalfH: CGFloat = 3.0
            let btRightX = centerX + 2.0
            let btLeftX = centerX - 1.7
            let btMidOffset: CGFloat = 1.5

            let btPath = CGMutablePath()
            btPath.move(to: CGPoint(x: btLeftX, y: btCenterY + btMidOffset))
            btPath.addLine(to: CGPoint(x: btRightX, y: btCenterY - btMidOffset))
            btPath.addLine(to: CGPoint(x: centerX, y: btCenterY - btHalfH))
            btPath.addLine(to: CGPoint(x: centerX, y: btCenterY + btHalfH))
            btPath.addLine(to: CGPoint(x: btRightX, y: btCenterY + btMidOffset))
            btPath.addLine(to: CGPoint(x: btLeftX, y: btCenterY - btMidOffset))

            ctx.addPath(btPath)
            ctx.setLineWidth(1.2)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.strokePath()

            // Signal arc above the lid (shown when enabled)
            if enabled {
                let arcPath = CGMutablePath()
                arcPath.addArc(
                    center: CGPoint(x: centerX, y: screenRect.maxY - 0.8),
                    radius: 3.6,
                    startAngle: CGFloat.pi * 0.25,
                    endAngle: CGFloat.pi * 0.75,
                    clockwise: false
                )
                ctx.addPath(arcPath)
                ctx.setLineWidth(1.25)
                ctx.setLineCap(.round)
                ctx.strokePath()
            } else {
                // Transparent cutout behind the slash (Apple SF Symbol `.slash` style)
                let slashStart = CGPoint(x: 3.2, y: 15.8)
                let slashEnd = CGPoint(x: 16.8, y: 1.6)

                ctx.saveGState()
                ctx.setBlendMode(.clear)
                ctx.beginPath()
                ctx.move(to: slashStart)
                ctx.addLine(to: slashEnd)
                ctx.setLineWidth(3.4)
                ctx.setLineCap(.round)
                ctx.strokePath()
                ctx.restoreGState()

                // Foreground slash
                ctx.beginPath()
                ctx.move(to: slashStart)
                ctx.addLine(to: slashEnd)
                ctx.setLineWidth(1.55)
                ctx.setLineCap(.round)
                ctx.strokePath()
            }

            return true
        }

        image.isTemplate = true
        image.accessibilityDescription = enabled ? "bt-flapper enabled" : "bt-flapper disabled"
        return image
    }
}
