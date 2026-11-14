// Draws the Coach app icon (Garden theme) and writes a 1024×1024 PNG.
// Usage: swift scripts/make-icon.swift <output.png>   (scripts/make-icon.sh turns it into AppIcon.icns)
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

// macOS icon grid: 824pt body centred in a 1024 canvas, ~185pt corner radius.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

// Soft drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
rgb(0.55, 0.78, 0.55).setFill()
shape.fill()
ctx.restoreGState()

ctx.saveGState()
shape.addClip()

// Sky: soft morning gradient, pale green at the horizon to warm cream at the top.
NSGradient(colors: [rgb(0.72, 0.88, 0.66), rgb(0.88, 0.94, 0.78), rgb(0.99, 0.96, 0.84)])!
    .draw(in: body, angle: 90)

// Sun, top right.
let sun = CGRect(x: 640, y: 640, width: 190, height: 190)
NSGradient(colors: [rgb(1.0, 0.86, 0.42), rgb(0.98, 0.70, 0.28)])!
    .draw(in: NSBezierPath(ovalIn: sun), angle: -60)

// Soil: a rounded hill along the bottom.
let soil = NSBezierPath()
soil.move(to: pt(body.minX, 300))
soil.curve(to: pt(body.maxX, 300), controlPoint1: pt(330, 410), controlPoint2: pt(700, 410))
soil.line(to: pt(body.maxX, body.minY))
soil.line(to: pt(body.minX, body.minY))
soil.close()
NSGradient(colors: [rgb(0.42, 0.28, 0.18), rgb(0.58, 0.40, 0.26)])!.draw(in: soil, angle: 90)
ctx.restoreGState()

// Sprout: a curved stem with two big leaves.
let leafDark = rgb(0.16, 0.50, 0.24), leafLight = rgb(0.40, 0.76, 0.36)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: NSColor.black.withAlphaComponent(0.25).cgColor)
ctx.beginTransparencyLayer(auxiliaryInfo: nil)

let stem = NSBezierPath()
stem.move(to: pt(512, 352))
stem.curve(to: pt(500, 640), controlPoint1: pt(470, 450), controlPoint2: pt(530, 560))
stem.lineWidth = 34
stem.lineCapStyle = .round
leafDark.setStroke()
stem.stroke()

func leaf(base: CGPoint, tip: CGPoint, c1: CGPoint, c2: CGPoint) {
    let p = NSBezierPath()
    p.move(to: base)
    p.curve(to: tip, controlPoint1: c1, controlPoint2: c1)
    p.curve(to: base, controlPoint1: c2, controlPoint2: c2)
    p.close()
    NSGradient(colors: [leafDark, leafLight])!.draw(in: p, angle: 30)
    // Midrib.
    let rib = NSBezierPath()
    rib.move(to: base)
    rib.curve(to: pt(base.x + (tip.x - base.x) * 0.8, base.y + (tip.y - base.y) * 0.8),
              controlPoint1: pt((base.x + tip.x) / 2, (base.y + tip.y) / 2 + 20),
              controlPoint2: pt((base.x + tip.x) / 2, (base.y + tip.y) / 2 + 20))
    rib.lineWidth = 10
    rib.lineCapStyle = .round
    rgb(1, 1, 1, 0.35).setStroke()
    rib.stroke()
}
leaf(base: pt(500, 600), tip: pt(230, 760), c1: pt(250, 590), c2: pt(470, 790))
leaf(base: pt(508, 620), tip: pt(760, 700), c1: pt(600, 830), c2: pt(740, 560))

ctx.endTransparencyLayer()
ctx.restoreGState()

// Water drop, falling toward the sprout (revising = watering).
let drop = NSBezierPath()
let dc = pt(290, 440), r: CGFloat = 62
drop.move(to: pt(dc.x, dc.y + r * 2.0))
drop.curve(to: pt(dc.x + r, dc.y), controlPoint1: pt(dc.x + r * 0.35, dc.y + r * 1.3), controlPoint2: pt(dc.x + r, dc.y + r * 0.6))
drop.appendArc(withCenter: dc, radius: r, startAngle: 0, endAngle: 180, clockwise: true)
drop.curve(to: pt(dc.x, dc.y + r * 2.0), controlPoint1: pt(dc.x - r, dc.y + r * 0.6), controlPoint2: pt(dc.x - r * 0.35, dc.y + r * 1.3))
drop.close()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: NSColor.black.withAlphaComponent(0.25).cgColor)
NSGradient(colors: [rgb(0.22, 0.52, 0.86), rgb(0.48, 0.76, 0.98)])!.draw(in: drop, angle: 70)
ctx.restoreGState()
rgb(1, 1, 1, 0.7).setFill()
NSBezierPath(ovalIn: CGRect(x: dc.x - 30, y: dc.y + 2, width: 18, height: 30)).fill()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
