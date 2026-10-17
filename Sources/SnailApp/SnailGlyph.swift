import AppKit

/// Snail-shell glyph matching the app icon, drawn as a template image so the menu bar tints it.
/// Outline when off; filled with the spiral cut out (like the app icon) when on.
enum SnailGlyph {
    static func image(filled: Bool, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            draw(in: rect, filled: filled)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Snail"
        return image
    }

    /// Geometry is authored on an 18×18 grid (y down) and scaled to `rect`.
    private static func draw(in rect: NSRect, filled: Bool) {
        let s = rect.width / 18
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: rect.minX + x * s, y: rect.minY + y * s) }

        let shell = NSBezierPath()
        shell.move(to: p(2.3, 15.2))
        shell.line(to: p(2.1, 9.2))
        shell.curve(to: p(9.6, 1.9), controlPoint1: p(2.0, 5.0), controlPoint2: p(5.4, 1.9))
        shell.curve(to: p(16.9, 9.6), controlPoint1: p(13.9, 1.9), controlPoint2: p(16.9, 5.3))
        shell.curve(to: p(10.9, 16.1), controlPoint1: p(16.9, 13.4), controlPoint2: p(14.3, 16.1))
        shell.curve(to: p(2.3, 15.2), controlPoint1: p(7.6, 16.1), controlPoint2: p(4.4, 15.8))
        shell.close()

        let spiral = spiralPath(center: p(10.3, 10.1), scale: s)
        spiral.lineWidth = 1.5 * s
        spiral.lineCapStyle = .round

        NSColor.black.set()
        if filled {
            shell.fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            spiral.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        } else {
            shell.lineWidth = 1.5 * s
            shell.lineJoinStyle = .round
            shell.stroke()
            spiral.stroke()
        }
    }

    /// Archimedean spiral from a small inner radius outwards, ending toward the shell's lower right.
    private static func spiralPath(center: NSPoint, scale s: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let turns: CGFloat = 1.75
        let startRadius: CGFloat = 0.7 * s
        let endRadius: CGFloat = 4.9 * s
        let startAngle: CGFloat = .pi  // outer end lands pointing down, merging into the shell base like the icon
        let steps = 90
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let angle = startAngle + t * turns * 2 * .pi
            let r = startRadius + (endRadius - startRadius) * t
            let pt = NSPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
            i == 0 ? path.move(to: pt) : path.line(to: pt)
        }
        return path
    }
}
