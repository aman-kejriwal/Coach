import AppKit

/// The menu bar icon: the app icon's "revise again" circular arrow around a brain, as a template
/// image (macOS tints it for light/dark menu bars and highlights). The due count is drawn into the
/// same image so the label is always a single, reliably rendered image.
enum MenuBarIcon {
    static func image(dueCount: Int) -> NSImage {
        let height: CGFloat = 18
        let glyph: CGFloat = 18
        let countText = dueCount > 0 ? (dueCount > 99 ? "99+" : "\(dueCount)") as NSString : nil
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
        let textAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textSize = countText?.size(withAttributes: textAttrs) ?? .zero
        let width = glyph + (countText == nil ? 0 : 3 + ceil(textSize.width))

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            drawGlyph(in: CGRect(x: 0, y: 0, width: glyph, height: height))
            if let countText {
                countText.draw(at: CGPoint(x: glyph + 3, y: (height - textSize.height) / 2), withAttributes: textAttrs)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = dueCount > 0 ? "Coach, \(dueCount) to revise today" : "Coach"
        return image
    }

    static func drawGlyph(in rect: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2 - 1.6
        let rad = { (d: CGFloat) in d * .pi / 180 }
        let gapStart: CGFloat = 58, gapEnd: CGFloat = 122

        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setFillColor(NSColor.black.cgColor)

        // Ring: from the top-left round to just before the arrow head at the top-right.
        ctx.setLineWidth(1.7)
        ctx.setLineCap(.round)
        ctx.addArc(center: center, radius: radius, startAngle: rad(gapEnd), endAngle: rad(gapStart + 360 - 14), clockwise: false)
        ctx.strokePath()

        // Arrow head pointing into the gap (counter-clockwise travel).
        let a = rad(gapStart - 4)
        let tip = CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
        let t = CGPoint(x: -sin(a), y: cos(a))   // direction of travel
        let n = CGPoint(x: cos(a), y: sin(a))    // outward
        let length: CGFloat = 5.2, half: CGFloat = 3.1
        let apex = CGPoint(x: tip.x + t.x * length * 0.65, y: tip.y + t.y * length * 0.65)
        let base = CGPoint(x: tip.x - t.x * length * 0.35, y: tip.y - t.y * length * 0.35)
        ctx.move(to: apex)
        ctx.addLine(to: CGPoint(x: base.x + n.x * half, y: base.y + n.y * half))
        ctx.addLine(to: CGPoint(x: base.x - n.x * half, y: base.y - n.y * half))
        ctx.closePath()
        ctx.fillPath()

        // Brain in the middle.
        let config = NSImage.SymbolConfiguration(pointSize: rect.width * 0.42, weight: .bold)
        if let brain = NSImage(systemSymbolName: "brain", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let s = brain.size
            brain.draw(in: CGRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height))
        } else {
            ctx.fillEllipse(in: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5))
        }
    }
}
