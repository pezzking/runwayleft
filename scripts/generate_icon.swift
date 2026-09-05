#!/usr/bin/env swift
//
// Generates the RunwayLeft app icon and menu bar glyphs from vector code.
//
//   swift scripts/generate_icon.swift preview <dir>            # side-by-side candidates
//   swift scripts/generate_icon.swift export <variant> <dir>    # AppIcon.icns + PNGs into <dir>
//
// Variants: runway (bold perspective runway), dial (runway converging on a
// quota gauge), gauge (dial with a runway strip below).

import AppKit

// MARK: - Palette

enum Palette {
    static let navyTop = NSColor(red: 0.13, green: 0.27, blue: 0.45, alpha: 1)
    static let navyBottom = NSColor(red: 0.04, green: 0.08, blue: 0.15, alpha: 1)
    static let ink = NSColor(red: 0.05, green: 0.09, blue: 0.17, alpha: 1)
    static let teal = NSColor(red: 0.12, green: 0.80, blue: 0.78, alpha: 1)
    static let mint = NSColor(red: 0.35, green: 0.93, blue: 0.62, alpha: 1)
    static let lime = NSColor(red: 0.74, green: 1.00, blue: 0.40, alpha: 1)
    static let amber = NSColor(red: 1.00, green: 0.70, blue: 0.15, alpha: 1)
    static let red = NSColor(red: 1.00, green: 0.32, blue: 0.30, alpha: 1)
    static let white = NSColor.white
}

// MARK: - Drawing helpers

func bitmap(_ px: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
}

func render(_ px: Int, _ body: (CGContext, CGFloat) -> Void) -> NSBitmapImageRep {
    let rep = bitmap(px)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.setShouldAntialias(true)
    cg.interpolationQuality = .high
    body(cg, CGFloat(px))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func gradient(_ colors: [NSColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map { $0.cgColor } as CFArray, locations: locations)!
}

/// Coordinate frame of the inset icon square (Apple's 824/1024 grid).
struct Frame {
    let origin: CGPoint
    let side: CGFloat
    func p(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: origin.x + u * side, y: origin.y + v * side) }
    func l(_ f: CGFloat) -> CGFloat { f * side }
}

func iconFrame(_ s: CGFloat) -> Frame {
    let side = s * 0.805
    return Frame(origin: CGPoint(x: (s - side) / 2, y: (s - side) / 2), side: side)
}

func squircle(_ f: Frame) -> CGPath {
    let r = f.side * 0.2237
    return CGPath(roundedRect: CGRect(origin: f.origin, size: CGSize(width: f.side, height: f.side)), cornerWidth: r, cornerHeight: r, transform: nil)
}

/// Rounded-square backdrop with the standard soft shadow and a navy gradient.
func drawBackdrop(_ cg: CGContext, _ s: CGFloat, glowAt: CGPoint?, glowColor: NSColor) {
    let f = iconFrame(s)
    let path = squircle(f)

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    cg.addPath(path)
    cg.setFillColor(Palette.navyBottom.cgColor)
    cg.fillPath()
    cg.restoreGState()

    cg.saveGState()
    cg.addPath(path)
    cg.clip()
    cg.drawLinearGradient(
        gradient([Palette.navyTop, Palette.navyBottom], [0, 1]),
        start: f.p(0, 1), end: f.p(1, 0), options: []
    )
    if let glow = glowAt {
        cg.drawRadialGradient(
            gradient([glowColor.withAlphaComponent(0.45), glowColor.withAlphaComponent(0)], [0, 1]),
            startCenter: glow, startRadius: 0, endCenter: glow, endRadius: f.l(0.55), options: []
        )
    }
    // Subtle top sheen.
    cg.drawLinearGradient(
        gradient([NSColor.white.withAlphaComponent(0.10), NSColor.white.withAlphaComponent(0)], [0, 1]),
        start: f.p(0.5, 1), end: f.p(0.5, 0.55), options: []
    )
    cg.restoreGState()
}

// MARK: - Variant: runway

struct RunwayGeometry {
    var bottomV: CGFloat = 0.11
    var topV: CGFloat = 0.72
    var bottomHalf: CGFloat = 0.27
    var topHalf: CGFloat = 0.048

    func y(_ t: CGFloat) -> CGFloat { bottomV + (topV - bottomV) * t }
    func half(_ t: CGFloat) -> CGFloat { bottomHalf + (topHalf - bottomHalf) * t }
}

/// The runway shape drawn into the current context. `fill` paints the surface;
/// dashes are cut out (template) or painted in ink (icon).
func drawRunway(_ cg: CGContext, _ f: Frame, geometry g: RunwayGeometry, surface: (CGContext) -> Void, cutDashes: Bool, lights: Bool, horizonLight: Bool) {
    let outline = CGMutablePath()
    outline.move(to: f.p(0.5 - g.half(0), g.y(0)))
    outline.addLine(to: f.p(0.5 + g.half(0), g.y(0)))
    outline.addLine(to: f.p(0.5 + g.half(1), g.y(1)))
    outline.addLine(to: f.p(0.5 - g.half(1), g.y(1)))
    outline.closeSubpath()

    cg.saveGState()
    cg.addPath(outline)
    cg.clip()
    surface(cg)
    cg.restoreGState()

    // Centerline dashes, foreshortened toward the horizon.
    let count = 6
    for i in 0..<count {
        let t0 = pow(CGFloat(i) / CGFloat(count), 0.62)
        let len = 0.075 * (1 - 0.82 * t0)
        let t1 = min(1, t0 + len / (g.topV - g.bottomV))
        let w0 = 0.030 * (1 - t0) + 0.005
        let w1 = 0.030 * (1 - t1) + 0.005
        let dash = CGMutablePath()
        dash.move(to: f.p(0.5 - w0, g.y(t0)))
        dash.addLine(to: f.p(0.5 + w0, g.y(t0)))
        dash.addLine(to: f.p(0.5 + w1, g.y(t1)))
        dash.addLine(to: f.p(0.5 - w1, g.y(t1)))
        dash.closeSubpath()
        cg.saveGState()
        cg.addPath(dash)
        if cutDashes {
            cg.setBlendMode(.clear)
            cg.setFillColor(NSColor.black.cgColor)
        } else {
            cg.setFillColor(Palette.ink.cgColor)
        }
        cg.fillPath()
        cg.restoreGState()
    }

    if lights {
        for i in 0..<count {
            let t = pow(CGFloat(i) / CGFloat(count), 0.62) + 0.03
            let r = f.l(0.014 * (1 - t) + 0.004)
            for side: CGFloat in [-1, 1] {
                let c = f.p(0.5 + side * (g.half(t) + 0.035 * (1 - t) + 0.012), g.y(t))
                cg.setFillColor(Palette.white.withAlphaComponent(0.9).cgColor)
                cg.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            }
        }
    }

    if horizonLight {
        let c = f.p(0.5, g.topV + 0.035)
        cg.saveGState()
        cg.drawRadialGradient(
            gradient([Palette.lime.withAlphaComponent(0.75), Palette.lime.withAlphaComponent(0)], [0, 1]),
            startCenter: c, startRadius: 0, endCenter: c, endRadius: f.l(0.13), options: []
        )
        cg.restoreGState()
        let r = f.l(0.028)
        cg.setFillColor(Palette.white.cgColor)
        cg.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
}

func renderRunwayIcon(_ px: Int) -> NSBitmapImageRep {
    render(px) { cg, s in
        let f = iconFrame(s)
        // Wider, lower top edge so it reads as a runway rather than a spire.
        let g = RunwayGeometry(bottomV: 0.10, topV: 0.66, bottomHalf: 0.30, topHalf: 0.085)
        drawBackdrop(cg, s, glowAt: f.p(0.5, g.topV + 0.02), glowColor: Palette.teal)

        cg.saveGState()
        cg.addPath(squircle(f))
        cg.clip()

        // Horizon band behind the far end.
        cg.drawLinearGradient(
            gradient([Palette.teal.withAlphaComponent(0), Palette.teal.withAlphaComponent(0.35), Palette.teal.withAlphaComponent(0)], [0, 0.5, 1]),
            start: f.p(0.5, g.topV - 0.04), end: f.p(0.5, g.topV + 0.10), options: []
        )

        // Runway surface: lime at the near end fading to teal at the horizon.
        drawRunway(cg, f, geometry: g, surface: { cg in
            cg.drawLinearGradient(
                gradient([Palette.lime, Palette.mint, Palette.teal.withAlphaComponent(0.9)], [0, 0.55, 1]),
                start: f.p(0.5, g.bottomV), end: f.p(0.5, g.topV), options: []
            )
        }, cutDashes: false, lights: false, horizonLight: false)

        // Ground shadow under the near end for lift.
        cg.drawLinearGradient(
            gradient([NSColor.black.withAlphaComponent(0.35), NSColor.black.withAlphaComponent(0)], [0, 1]),
            start: f.p(0.5, 0), end: f.p(0.5, 0.16), options: []
        )
        cg.restoreGState()
    }
}

// MARK: - Variant: gauge

func renderGaugeIcon(_ px: Int) -> NSBitmapImageRep {
    render(px) { cg, s in
        let f = iconFrame(s)
        let center = f.p(0.5, 0.44)
        drawBackdrop(cg, s, glowAt: f.p(0.5, 0.5), glowColor: Palette.teal)

        cg.saveGState()
        cg.addPath(squircle(f))
        cg.clip()

        let radius = f.l(0.30)
        let width = f.l(0.115)
        let startAngle: CGFloat = 225 * .pi / 180
        let endAngle: CGFloat = -45 * .pi / 180

        // Track
        cg.setLineCap(.round)
        cg.setLineWidth(width)
        cg.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
        cg.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        cg.strokePath()

        // Colored arc in segments: mint → lime → amber → red
        let stops: [(CGFloat, NSColor)] = [(0, Palette.mint), (0.45, Palette.lime), (0.75, Palette.amber), (1, Palette.red)]
        let segments = 96
        let filled: CGFloat = 0.68
        for i in 0..<Int(CGFloat(segments) * filled) {
            let t0 = CGFloat(i) / CGFloat(segments)
            let t1 = CGFloat(i + 1) / CGFloat(segments) + 0.004
            var color = Palette.mint
            for j in 0..<(stops.count - 1) where t0 >= stops[j].0 && t0 <= stops[j + 1].0 {
                let k = (t0 - stops[j].0) / (stops[j + 1].0 - stops[j].0)
                color = stops[j].1.blended(withFraction: k, of: stops[j + 1].1) ?? color
            }
            let a0 = startAngle - t0 * (270 * .pi / 180)
            let a1 = startAngle - t1 * (270 * .pi / 180)
            cg.setStrokeColor(color.cgColor)
            cg.setLineCap(i == 0 ? .round : .butt)
            cg.addArc(center: center, radius: radius, startAngle: a0, endAngle: a1, clockwise: true)
            cg.strokePath()
        }

        // Needle at the current fill level
        let needleAngle = startAngle - filled * (270 * .pi / 180)
        let tip = CGPoint(x: center.x + cos(needleAngle) * (radius - width * 0.1), y: center.y + sin(needleAngle) * (radius - width * 0.1))
        cg.setStrokeColor(Palette.white.cgColor)
        cg.setLineWidth(f.l(0.045))
        cg.setLineCap(.round)
        cg.move(to: center)
        cg.addLine(to: tip)
        cg.strokePath()
        let hub = f.l(0.075)
        cg.setFillColor(Palette.white.cgColor)
        cg.fillEllipse(in: CGRect(x: center.x - hub, y: center.y - hub, width: 2 * hub, height: 2 * hub))
        cg.setFillColor(Palette.ink.cgColor)
        cg.fillEllipse(in: CGRect(x: center.x - hub * 0.45, y: center.y - hub * 0.45, width: hub * 0.9, height: hub * 0.9))

        // Small runway dashes under the dial as the app's motif
        let g = RunwayGeometry(bottomV: 0.07, topV: 0.30, bottomHalf: 0.16, topHalf: 0.04)
        drawRunway(cg, f, geometry: g, surface: { cg in
            cg.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
            cg.fill(CGRect(origin: .zero, size: CGSize(width: s, height: s)))
        }, cutDashes: false, lights: false, horizonLight: false)

        cg.restoreGState()
    }
}

// MARK: - Variant: dial (runway converging on the gauge hub)

func renderDialIcon(_ px: Int) -> NSBitmapImageRep {
    render(px) { cg, s in
        let f = iconFrame(s)
        let hubV: CGFloat = 0.47
        let center = f.p(0.5, hubV)
        drawBackdrop(cg, s, glowAt: center, glowColor: Palette.teal)

        cg.saveGState()
        cg.addPath(squircle(f))
        cg.clip()

        // Runway enters through the dial's opening and vanishes at the hub.
        let g = RunwayGeometry(bottomV: 0.05, topV: hubV, bottomHalf: 0.21, topHalf: 0.012)
        drawRunway(cg, f, geometry: g, surface: { cg in
            cg.drawLinearGradient(
                gradient([Palette.lime, Palette.mint, Palette.teal.withAlphaComponent(0.6)], [0, 0.5, 1]),
                start: f.p(0.5, g.bottomV), end: f.p(0.5, g.topV), options: []
            )
        }, cutDashes: false, lights: false, horizonLight: false)

        let radius = f.l(0.31)
        let width = f.l(0.105)
        let startAngle: CGFloat = 225 * .pi / 180
        let endAngle: CGFloat = -45 * .pi / 180
        let filled: CGFloat = 0.66

        cg.setLineCap(.round)
        cg.setLineWidth(width)
        cg.setStrokeColor(NSColor.white.withAlphaComponent(0.13).cgColor)
        cg.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        cg.strokePath()

        let stops: [(CGFloat, NSColor)] = [(0, Palette.mint), (0.45, Palette.lime), (0.75, Palette.amber), (1, Palette.red)]
        let segments = 96
        for i in 0..<Int(CGFloat(segments) * filled) {
            let t0 = CGFloat(i) / CGFloat(segments)
            let t1 = CGFloat(i + 1) / CGFloat(segments) + 0.004
            var color = Palette.mint
            for j in 0..<(stops.count - 1) where t0 >= stops[j].0 && t0 <= stops[j + 1].0 {
                let k = (t0 - stops[j].0) / (stops[j + 1].0 - stops[j].0)
                color = stops[j].1.blended(withFraction: k, of: stops[j + 1].1) ?? color
            }
            cg.setStrokeColor(color.cgColor)
            cg.setLineCap(i == 0 ? .round : .butt)
            cg.addArc(center: center, radius: radius,
                      startAngle: startAngle - t0 * (270 * .pi / 180),
                      endAngle: startAngle - t1 * (270 * .pi / 180), clockwise: true)
            cg.strokePath()
        }

        let needleAngle = startAngle - filled * (270 * .pi / 180)
        let tip = CGPoint(x: center.x + cos(needleAngle) * (radius - width * 0.15), y: center.y + sin(needleAngle) * (radius - width * 0.15))
        cg.saveGState()
        cg.setShadow(offset: .zero, blur: f.l(0.02), color: NSColor.black.withAlphaComponent(0.5).cgColor)
        cg.setStrokeColor(Palette.white.cgColor)
        cg.setLineWidth(f.l(0.04))
        cg.setLineCap(.round)
        cg.move(to: center)
        cg.addLine(to: tip)
        cg.strokePath()
        cg.restoreGState()

        let hub = f.l(0.07)
        cg.setFillColor(Palette.white.cgColor)
        cg.fillEllipse(in: CGRect(x: center.x - hub, y: center.y - hub, width: 2 * hub, height: 2 * hub))
        cg.setFillColor(Palette.ink.cgColor)
        cg.fillEllipse(in: CGRect(x: center.x - hub * 0.42, y: center.y - hub * 0.42, width: hub * 0.84, height: hub * 0.84))

        cg.restoreGState()
    }
}

// MARK: - Menu bar glyphs

/// Runway alone, for the menu bar: filled white with the dashes cut out.
func renderRunwayGlyph(_ px: Int, warning: Bool) -> NSBitmapImageRep {
    render(px) { cg, s in
        let f = Frame(origin: .zero, side: s)
        let g = RunwayGeometry(bottomV: 0.06, topV: 0.80, bottomHalf: 0.44, topHalf: 0.075)
        drawRunway(cg, f, geometry: g, surface: { cg in
            if warning {
                cg.drawLinearGradient(gradient([Palette.red, Palette.amber], [0, 1]), start: f.p(0.5, g.bottomV), end: f.p(0.5, g.topV), options: [])
            } else {
                cg.setFillColor(NSColor.black.cgColor)
                cg.fill(CGRect(origin: .zero, size: CGSize(width: s, height: s)))
            }
        }, cutDashes: true, lights: false, horizonLight: false)

        // Horizon light as a plain dot
        let c = f.p(0.5, 0.905)
        let r = f.l(0.075)
        cg.setFillColor(warning ? Palette.amber.cgColor : NSColor.black.cgColor)
        cg.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
}

func renderGaugeGlyph(_ px: Int, warning: Bool) -> NSBitmapImageRep {
    render(px) { cg, s in
        let center = CGPoint(x: s / 2, y: s * 0.46)
        let radius = s * 0.34
        let width = s * 0.14
        let color = warning ? Palette.red : NSColor.black
        cg.setLineCap(.round)
        cg.setLineWidth(width)
        cg.setStrokeColor(color.cgColor)
        cg.addArc(center: center, radius: radius, startAngle: 225 * .pi / 180, endAngle: -45 * .pi / 180, clockwise: true)
        cg.strokePath()
        let angle: CGFloat = (225 - 0.68 * 270) * .pi / 180
        cg.setLineWidth(s * 0.09)
        cg.move(to: center)
        cg.addLine(to: CGPoint(x: center.x + cos(angle) * radius * 0.85, y: center.y + sin(angle) * radius * 0.85))
        cg.strokePath()
        cg.setFillColor(color.cgColor)
        let hub = s * 0.11
        cg.fillEllipse(in: CGRect(x: center.x - hub, y: center.y - hub, width: 2 * hub, height: 2 * hub))
    }
}

// MARK: - Export

func png(_ rep: NSBitmapImageRep) -> Data { rep.representation(using: .png, properties: [:])! }

func write(_ rep: NSBitmapImageRep, to path: String) throws {
    try png(rep).write(to: URL(fileURLWithPath: path))
}

func icon(for variant: String, _ px: Int) -> NSBitmapImageRep {
    switch variant {
    case "gauge": return renderGaugeIcon(px)
    case "dial": return renderDialIcon(px)
    default: return renderRunwayIcon(px)
    }
}

func glyph(for variant: String, _ px: Int, warning: Bool) -> NSBitmapImageRep {
    variant == "runway" ? renderRunwayGlyph(px, warning: warning) : renderGaugeGlyph(px, warning: warning)
}

func exportAssets(variant: String, into dir: String) throws {
    let fm = FileManager.default
    try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

    let iconset = dir + "/AppIcon.iconset"
    try? fm.removeItem(atPath: iconset)
    try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        try write(icon(for: variant, base), to: "\(iconset)/icon_\(base)x\(base).png")
        try write(icon(for: variant, base * 2), to: "\(iconset)/icon_\(base)x\(base)@2x.png")
    }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", iconset, "-o", dir + "/AppIcon.icns"]
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { throw NSError(domain: "iconutil", code: Int(task.terminationStatus)) }
    try? fm.removeItem(atPath: iconset)

    try write(icon(for: variant, 256), to: dir + "/appicon.png")
    try write(glyph(for: variant, 64, warning: false), to: dir + "/menubar_glyph.png")
    try write(glyph(for: variant, 64, warning: true), to: dir + "/menubar_glyph_warning.png")
    print("exported \(variant) icon set to \(dir)")
}

func exportPreview(into dir: String) throws {
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let variants = ["runway", "dial", "gauge"]
    let cellW = 560, cellH = 200
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: cellW * variants.count, pixelsHigh: cellH * 2, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.interpolationQuality = .high

    for (column, variant) in variants.enumerated() {
        for (row, dark) in [true, false].enumerated() {
            let ox = CGFloat(column * cellW), oy = CGFloat((1 - row) * cellH)
            cg.setFillColor((dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.92, alpha: 1)).cgColor)
            cg.fill(CGRect(x: ox, y: oy, width: CGFloat(cellW), height: CGFloat(cellH)))

            var x = ox + 16
            for size in [160, 64, 32, 16] {
                let img = NSImage(size: NSSize(width: size, height: size))
                img.addRepresentation(icon(for: variant, size))
                img.draw(in: CGRect(x: x, y: oy + (CGFloat(cellH) - CGFloat(size)) / 2, width: CGFloat(size), height: CGFloat(size)))
                x += CGFloat(size) + 18
            }
            // Menu bar glyph as it would be tinted (white on dark, black on light), at 16pt shown 3x.
            for warning in [false, true] {
                let g = glyph(for: variant, 64, warning: warning)
                let tinted = NSImage(size: NSSize(width: 64, height: 64))
                tinted.lockFocus()
                if warning {
                    NSImage(size: NSSize(width: 64, height: 64)).draw(in: .zero)
                    let src = NSImage(size: NSSize(width: 64, height: 64)); src.addRepresentation(g)
                    src.draw(in: CGRect(x: 0, y: 0, width: 64, height: 64))
                } else {
                    let src = NSImage(size: NSSize(width: 64, height: 64)); src.addRepresentation(g)
                    src.draw(in: CGRect(x: 0, y: 0, width: 64, height: 64))
                    (dark ? NSColor.white : NSColor.black).set()
                    CGRect(x: 0, y: 0, width: 64, height: 64).fill(using: .sourceIn)
                }
                tinted.unlockFocus()
                tinted.draw(in: CGRect(x: x, y: oy + CGFloat(cellH) / 2 - 24, width: 48, height: 48))
                x += 60
            }
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    try write(rep, to: dir + "/icon-candidates.png")
    print("wrote \(dir)/icon-candidates.png")
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: generate_icon.swift preview <dir> | export <runway|gauge> <dir>")
    exit(2)
}

do {
    switch args[1] {
    case "preview":
        try exportPreview(into: args[2])
    case "export":
        guard args.count >= 4 else { print("export needs <variant> <dir>"); exit(2) }
        try exportAssets(variant: args[2], into: args[3])
    default:
        print("unknown command \(args[1])"); exit(2)
    }
} catch {
    print("error: \(error)")
    exit(1)
}
