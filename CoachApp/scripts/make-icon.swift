// Draws the Coach app icon and writes a 1024×1024 PNG.
// Usage: swift scripts/make-icon.swift <output.png>   (scripts/make-icon.sh turns it into AppIcon.icns)
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: 824pt body centred in a 1024 canvas, ~185pt corner radius.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

// Soft drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor(calibratedRed: 0.27, green: 0.22, blue: 0.75, alpha: 1).setFill()
shape.fill()
ctx.restoreGState()

// Background gradient: deep indigo (bottom) → violet (top).
ctx.saveGState()
shape.addClip()
NSGradient(colors: [
    NSColor(calibratedRed: 0.20, green: 0.16, blue: 0.62, alpha: 1),
    NSColor(calibratedRed: 0.38, green: 0.27, blue: 0.90, alpha: 1),
    NSColor(calibratedRed: 0.62, green: 0.40, blue: 0.98, alpha: 1),
])!.draw(in: body, angle: 90)

// Glassy highlight on the top half.
NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    .draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
ctx.restoreGState()

let center = CGPoint(x: size / 2, y: size / 2 - 6)

// Revision cycle: a circular arrow running counter-clockwise, leaving a gap at the top,
// with the arrow head at the end pointing into the gap ("go round again").
let radius: CGFloat = 300
let lineWidth: CGFloat = 46
let gapStart: CGFloat = 62, gapEnd: CGFloat = 128 // degrees; the arc covers everything else
let white = NSColor.white.cgColor

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: NSColor.black.withAlphaComponent(0.25).cgColor)
ctx.beginTransparencyLayer(auxiliaryInfo: nil)

// Arc from gapEnd (top-left), counter-clockwise all the way round, to gapStart (top-right).
let rad = { (d: CGFloat) in d * .pi / 180 }
ctx.setStrokeColor(white)
ctx.setLineWidth(lineWidth)
ctx.setLineCap(.round)
ctx.addArc(center: center, radius: radius, startAngle: rad(gapEnd), endAngle: rad(gapStart + 360 - 8), clockwise: false)
ctx.strokePath()

// Arrow head at gapStart. Travel direction (counter-clockwise tangent) = (-sin a, cos a).
let a = rad(gapStart)
let tip = CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
let t = CGPoint(x: -sin(a), y: cos(a))
let n = CGPoint(x: cos(a), y: sin(a))
let headLength: CGFloat = 125, headHalfWidth: CGFloat = 72
let apex = CGPoint(x: tip.x + t.x * headLength * 0.7, y: tip.y + t.y * headLength * 0.7)
let base = CGPoint(x: tip.x - t.x * headLength * 0.3, y: tip.y - t.y * headLength * 0.3)
ctx.setFillColor(white)
ctx.setLineJoin(.round)
ctx.setLineWidth(18)
ctx.move(to: apex)
ctx.addLine(to: CGPoint(x: base.x + n.x * headHalfWidth, y: base.y + n.y * headHalfWidth))
ctx.addLine(to: CGPoint(x: base.x - n.x * headHalfWidth, y: base.y - n.y * headHalfWidth))
ctx.closePath()
ctx.drawPath(using: .fillStroke)

ctx.endTransparencyLayer()
ctx.restoreGState()

// Brain glyph in the middle (SF Symbols).
let config = NSImage.SymbolConfiguration(pointSize: 330, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let brain = NSImage(systemSymbolName: "brain", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let s = brain.size
    let rect = CGRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    brain.draw(in: rect)
    ctx.restoreGState()
}

// Small green "due" dot: the coach nudging you.
let dot = CGRect(x: center.x + 205, y: center.y - 300, width: 120, height: 120)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: NSColor.black.withAlphaComponent(0.3).cgColor)
NSColor(calibratedRed: 0.25, green: 0.88, blue: 0.55, alpha: 1).setFill()
NSBezierPath(ovalIn: dot).fill()
ctx.restoreGState()
NSColor.white.setStroke()
let check = NSBezierPath()
check.move(to: CGPoint(x: dot.minX + 32, y: dot.midY + 2))
check.line(to: CGPoint(x: dot.minX + 52, y: dot.midY - 20))
check.line(to: CGPoint(x: dot.maxX - 28, y: dot.midY + 24))
check.lineWidth = 16
check.lineCapStyle = .round
check.lineJoinStyle = .round
check.stroke()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
