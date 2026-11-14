import AppKit

/// The menu bar icon: a sprout (the Garden theme), as a template
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

    /// A sprout: a curved stem with two leaves, growing from a little mound of soil.
    static func drawGlyph(in rect: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = rect.width, h = rect.height
        let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: rect.minX + x * w, y: rect.minY + y * h) }

        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setLineCap(.round)

        // Soil mound.
        ctx.setLineWidth(1.7)
        ctx.move(to: p(0.14, 0.10))
        ctx.addQuadCurve(to: p(0.86, 0.10), control: p(0.5, 0.30))
        ctx.strokePath()

        // Stem.
        ctx.setLineWidth(1.6)
        ctx.move(to: p(0.5, 0.18))
        ctx.addQuadCurve(to: p(0.5, 0.62), control: p(0.44, 0.40))
        ctx.strokePath()

        // Left leaf (bigger) and right leaf.
        func leaf(from a: CGPoint, to b: CGPoint, bulge c1: CGPoint, _ c2: CGPoint) {
            ctx.move(to: a)
            ctx.addQuadCurve(to: b, control: c1)
            ctx.addQuadCurve(to: a, control: c2)
            ctx.fillPath()
        }
        leaf(from: p(0.49, 0.58), to: p(0.06, 0.90), bulge: p(0.12, 0.55), p(0.42, 0.95))
        leaf(from: p(0.52, 0.62), to: p(0.94, 0.80), bulge: p(0.66, 0.96), p(0.88, 0.56))
    }
}
