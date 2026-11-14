// Renders the K24 Screenshot Maker app icon (1024×1024 PNG):
// a film strip with a video frame, viewfinder capture corners and a camera badge.
// Usage: swift Resources/make_icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Vertical gradient (top color first) clipped to `path`.
func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil, path: CGPath, top: CGFloat, bottom: CGFloat) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func roundRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// MARK: Body (macOS icon grid: 824 pt, corner ≈ 185)
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = roundRect(body, 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: rgb(0x000000, 0.45))
ctx.addPath(bodyPath); ctx.setFillColor(rgb(0x161C2A)); ctx.fillPath()
ctx.restoreGState()
gradient([rgb(0x2C3A5C), rgb(0x121722)], path: bodyPath, top: body.maxY, bottom: body.minY)

ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()

// MARK: Film strip
let band = CGRect(x: 100, y: 262, width: 824, height: 500)
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: rgb(0x000000, 0.5))
ctx.setFillColor(rgb(0x0A0D13)); ctx.fill(band)
ctx.setShadow(offset: .zero, blur: 0, color: nil)
for row in [CGFloat(282), CGFloat(712)] {
    for k in 0..<11 {
        let hole = roundRect(CGRect(x: 120 + CGFloat(k) * 74, y: row, width: 44, height: 30), 7)
        ctx.addPath(hole); ctx.setFillColor(rgb(0xDCE2EC, 0.92)); ctx.fillPath()
    }
}

// MARK: Video frame with a sunset scene
let frame = CGRect(x: 150, y: 334, width: 724, height: 360)
let framePath = roundRect(frame, 16)
let horizon: CGFloat = 446
gradient([rgb(0x2A2F78), rgb(0x8C3F8F), rgb(0xF2684A), rgb(0xFFC069)], [0, 0.42, 0.78, 1],
         path: framePath, top: frame.maxY, bottom: horizon)

ctx.saveGState()
ctx.addPath(framePath); ctx.clip()
// Sun + glow
let sun = CGPoint(x: 600, y: horizon + 34)
let glow = CGGradient(colorsSpace: space, colors: [rgb(0xFFE7A8, 0.9), rgb(0xFFB060, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: sun, startRadius: 0, endCenter: sun, endRadius: 190, options: [])
ctx.addEllipse(in: CGRect(x: sun.x - 50, y: sun.y - 50, width: 100, height: 100))
ctx.setFillColor(rgb(0xFFF0C8)); ctx.fillPath()

func mountains(_ pts: [(CGFloat, CGFloat)], color: CGColor) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: frame.minX, y: horizon - 1))
    for (x, y) in pts { p.addLine(to: CGPoint(x: x, y: y)) }
    p.addLine(to: CGPoint(x: frame.maxX, y: horizon - 1))
    p.closeSubpath()
    ctx.addPath(p); ctx.setFillColor(color); ctx.fillPath()
}
mountains([(150, 520), (250, 600), (330, 545), (430, 640), (520, 540), (580, 575), (680, 500), (790, 590), (874, 530)],
          color: rgb(0x6B3B78))
mountains([(150, 480), (230, 540), (310, 500), (390, 570), (470, 470), (560, 505), (650, 455), (740, 520), (874, 470)],
          color: rgb(0x231C3A))
// Lake with reflection
let lake = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: horizon - frame.minY)
gradient([rgb(0xC8615C), rgb(0x3A2A55), rgb(0x161A33)], [0, 0.45, 1], path: CGPath(rect: lake, transform: nil),
         top: lake.maxY, bottom: lake.minY)
for (i, w) in [CGFloat(150), 110, 70, 40].enumerated() {
    let y = horizon - 18 - CGFloat(i) * 22
    ctx.addPath(roundRect(CGRect(x: sun.x - w / 2, y: y, width: w, height: 7), 3.5))
    ctx.setFillColor(rgb(0xFFE2A0, 0.75 - CGFloat(i) * 0.15)); ctx.fillPath()
}
ctx.restoreGState()
ctx.addPath(framePath); ctx.setStrokeColor(rgb(0xFFFFFF, 0.15)); ctx.setLineWidth(3); ctx.strokePath()

// MARK: Viewfinder capture corners
let vf = frame.insetBy(dx: 30, dy: 28)
let arm: CGFloat = 74
ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(17); ctx.setLineCap(.round); ctx.setLineJoin(.round)
for (cx, cy, dx, dy) in [(vf.minX, vf.maxY, 1.0, -1.0), (vf.maxX, vf.maxY, -1.0, -1.0),
                         (vf.minX, vf.minY, 1.0, 1.0), (vf.maxX, vf.minY, -1.0, 1.0)] {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: cx, y: cy + dy * arm))
    p.addLine(to: CGPoint(x: cx, y: cy))
    p.addLine(to: CGPoint(x: cx + dx * arm, y: cy))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: rgb(0x000000, 0.45))
    ctx.addPath(p); ctx.strokePath()
    ctx.restoreGState()
}
ctx.restoreGState() // body clip

// MARK: Camera badge
let c = CGPoint(x: 772, y: 252)
let r: CGFloat = 132
let badge = CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.55))
ctx.addPath(badge); ctx.setFillColor(rgb(0x1E72FF)); ctx.fillPath()
ctx.restoreGState()
gradient([rgb(0x5A9DFF), rgb(0x1257E0)], path: badge, top: c.y + r, bottom: c.y - r)
ctx.addPath(badge); ctx.setStrokeColor(rgb(0xFFFFFF, 0.95)); ctx.setLineWidth(11); ctx.strokePath()

// Camera glyph
let camBody = CGRect(x: c.x - 74, y: c.y - 56, width: 148, height: 100)
let bump = CGRect(x: c.x - 32, y: camBody.maxY - 12, width: 64, height: 34)
ctx.addPath(roundRect(bump, 10)); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
ctx.addPath(roundRect(camBody, 24)); ctx.fillPath()
let lensC = CGPoint(x: c.x, y: camBody.midY - 2)
ctx.addEllipse(in: CGRect(x: lensC.x - 36, y: lensC.y - 36, width: 72, height: 72))
ctx.setFillColor(rgb(0x1660EA)); ctx.fillPath()
ctx.addEllipse(in: CGRect(x: lensC.x - 20, y: lensC.y - 20, width: 40, height: 40))
ctx.setFillColor(rgb(0x0B3FA8)); ctx.fillPath()
ctx.addEllipse(in: CGRect(x: lensC.x + 2, y: lensC.y + 6, width: 13, height: 13))
ctx.setFillColor(rgb(0xFFFFFF, 0.9)); ctx.fillPath()
ctx.addEllipse(in: CGRect(x: camBody.maxX - 30, y: camBody.maxY - 26, width: 13, height: 13))
ctx.setFillColor(rgb(0x1660EA)); ctx.fillPath()

let img = ctx.makeImage()!
try! NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
