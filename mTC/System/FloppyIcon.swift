import AppKit

/// Монохромная дискета для строки меню (template-картинка: цвет подстраивается под тему).
enum FloppyIcon {
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let minX: CGFloat = 2, minY: CGFloat = 2, maxX: CGFloat = 16, maxY: CGFloat = 16
            let radius: CGFloat = 1.8, notch: CGFloat = 2.5

            let path = NSBezierPath()
            path.move(to: NSPoint(x: minX + radius, y: minY))
            path.appendArc(from: NSPoint(x: maxX, y: minY), to: NSPoint(x: maxX, y: minY + radius), radius: radius)
            path.line(to: NSPoint(x: maxX, y: maxY - notch))
            path.line(to: NSPoint(x: maxX - notch, y: maxY))
            path.appendArc(from: NSPoint(x: minX, y: maxY), to: NSPoint(x: minX, y: maxY - radius), radius: radius)
            path.appendArc(from: NSPoint(x: minX, y: minY), to: NSPoint(x: minX + radius, y: minY), radius: radius)
            path.close()

            // Вырезы: шторка сверху и этикетка из двух половин (две панели).
            path.append(NSBezierPath(rect: NSRect(x: 5.5, y: 11.5, width: 6.5, height: 3)))
            path.append(NSBezierPath(roundedRect: NSRect(x: 4, y: 3.5, width: 4.5, height: 5.5), xRadius: 0.8, yRadius: 0.8))
            path.append(NSBezierPath(roundedRect: NSRect(x: 9.5, y: 3.5, width: 4.5, height: 5.5), xRadius: 0.8, yRadius: 0.8))
            path.windingRule = .evenOdd

            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "mTC"
        return image
    }
}
