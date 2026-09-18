#!/usr/bin/env swift
// Draws the app icon. AppKit rather than a design tool: every size is rendered natively
// instead of resampled, the source is code in the repository, and it stays reproducible —
// the same reasoning as the menu bar icon, the README assets and the DMG background.
//
//   swift scripts/app-icon.swift <variant> <size> <out.png>
//   swift scripts/app-icon.swift sheet 0 preview.png      // all variants, several sizes
//
// Variants come from the name and from what the product actually looks like:
//
//   strip   the 8-LED plate you see in the menu bar, with an aura behind it.
//           Maximum continuity: the icon in your Dock is the thing in your menu bar.
//   aura    one lit dot inside concentric rings. Closest to the word "aura", and the
//           only one that stays legible when it's 16 points wide.
//   bar     a slice of menu bar with one LED lit. Tells you where the product lives.
//
// **Small sizes are drawn differently, not scaled down.** Eight LEDs at 16pt is under a
// point each — it turns to mush. Below 64pt each variant falls back to a simplified form.
// That's what the `simplified` flag is for.

import AppKit

let args = CommandLine.arguments
let variant = args.count > 1 ? args[1] : "sheet"
let requested = args.count > 2 ? CGFloat(Double(args[2]) ?? 1024) : 1024
let out = args.count > 3 ? args[3] : "icon.png"
// @2x 的圖是「同一個點尺寸、兩倍像素」，不是「兩倍點尺寸」——後者會讓 16pt@2x 套用
// 大尺寸的設計（8 顆 LED 擠在 32 像素裡），正是這支腳本刻意要避開的事。
let scaleArg = args.count > 4 ? CGFloat(Double(args[4]) ?? 1) : 1

// ---- palette. The state colours are the product's own; the plate matches IconPlate.
let plateDark  = NSColor(srgbRed: 0.078, green: 0.078, blue: 0.086, alpha: 1)
let plateLight = NSColor(srgbRed: 0.161, green: 0.161, blue: 0.180, alpha: 1)
let amber      = NSColor(srgbRed: 1.000, green: 0.624, blue: 0.039, alpha: 1)   // waiting
let green      = NSColor(srgbRed: 0.204, green: 0.780, blue: 0.349, alpha: 1)   // done
let ledOff     = NSColor(srgbRed: 1.000, green: 0.624, blue: 0.039, alpha: 0.18)

/// Apple's rounded-square silhouette, near enough. Radius is ~22.4% of the side.
func squircle(_ r: NSRect) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: r.width * 0.2237, yRadius: r.width * 0.2237)
}

/// A soft radial glow — this is the "aura" the product is named after, and it's the only
/// element every variant shares.
func glow(at c: NSPoint, radius: CGFloat, colour: NSColor, ctx: CGContext) {
    let cols = [colour.withAlphaComponent(0.55).cgColor,
                colour.withAlphaComponent(0.22).cgColor,
                colour.withAlphaComponent(0).cgColor] as CFArray
    guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: cols, locations: [0, 0.45, 1]) else { return }
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: c.x, y: c.y), startRadius: 0,
                           endCenter: CGPoint(x: c.x, y: c.y), endRadius: radius,
                           options: [])
}

func render(variant: String, side: CGFloat, ctx: CGContext) {
    let simplified = side < 64
    // Art sits inside the canvas with the margin macOS icons use.
    let inset = side * 0.09
    let art = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let mid = NSPoint(x: art.midX, y: art.midY)

    // Plate: a vertical gradient so it doesn't read as a flat black square.
    let plate = squircle(art)
    ctx.saveGState()
    plate.addClip()
    if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [plateLight.cgColor, plateDark.cgColor] as CFArray,
                          locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: art.maxY),
                               end: CGPoint(x: 0, y: art.minY), options: [])
    }

    switch variant {
    case "strip":
        // The real menu bar icon is a **wide, short** plate: 8 LEDs in 44×18pt. Drawing it
        // tall to fill a square canvas turns it into a barcode — that was the first attempt.
        // Keeping the true proportion is what makes it read as "the thing in my menu bar".
        let count = simplified ? 3 : 8
        let bandW = art.width * 0.78
        let bandH = bandW * (18.0 / 44.0)
        let band = NSRect(x: mid.x - bandW / 2, y: mid.y - bandH / 2, width: bandW, height: bandH)
        glow(at: mid, radius: bandW * 0.78, colour: amber, ctx: ctx)
        // The inner plate, same geometry as IconPlate: the icon contains the real icon.
        NSColor(srgbRed: 0.055, green: 0.055, blue: 0.063, alpha: 1).setFill()
        NSBezierPath(roundedRect: band, xRadius: bandH * 0.28, yRadius: bandH * 0.28).fill()
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10).setStroke()
        let bp = NSBezierPath(roundedRect: band.insetBy(dx: bandH * 0.02, dy: bandH * 0.02),
                              xRadius: bandH * 0.28, yRadius: bandH * 0.28)
        bp.lineWidth = bandH * 0.045
        bp.stroke()

        let pad = bandH * 0.20
        let inner = band.insetBy(dx: pad, dy: pad)
        let gap = inner.width * (simplified ? 0.09 : 0.055)
        let w = (inner.width - gap * CGFloat(count - 1)) / CGFloat(count)
        var x = inner.minX
        for i in 0..<count {
            // The last LED stays dark: "some of your sessions", not all of them.
            (i < count - 1 ? amber : ledOff).setFill()
            let r = NSRect(x: x, y: inner.minY, width: w, height: inner.height)
            NSBezierPath(roundedRect: r, xRadius: w * 0.4, yRadius: w * 0.4).fill()
            x += w + gap
        }

    case "aura":
        glow(at: mid, radius: art.width * 0.56, colour: amber, ctx: ctx)
        if !simplified {
            // Arcs, not full rings — a full ring reads as a record button or a target.
            // Open at the sides, it reads as light spreading.
            for (i, f) in [0.58, 0.82].enumerated() {
                amber.withAlphaComponent(i == 0 ? 0.50 : 0.24).setStroke()
                let rr = art.width * f / 2
                let arc = NSBezierPath()
                arc.appendArc(withCenter: mid, radius: rr, startAngle: 35, endAngle: 145)
                arc.lineWidth = art.width * (i == 0 ? 0.030 : 0.020)
                arc.lineCapStyle = .round
                arc.stroke()
                let arc2 = NSBezierPath()
                arc2.appendArc(withCenter: mid, radius: rr, startAngle: 215, endAngle: 325)
                arc2.lineWidth = art.width * (i == 0 ? 0.030 : 0.020)
                arc2.lineCapStyle = .round
                arc2.stroke()
            }
        }
        amber.setFill()
        let d = art.width * (simplified ? 0.44 : 0.30)
        NSBezierPath(ovalIn: NSRect(x: mid.x - d / 2, y: mid.y - d / 2, width: d, height: d)).fill()

    case "bar":
        // The menu bar sits at the TOP of your screen, so putting the strip in the middle
        // loses the whole point. High and thin reads as "up there", which is where you look.
        let barH = art.height * (simplified ? 0.26 : 0.17)
        let barY = art.maxY - art.height * (simplified ? 0.26 : 0.30)
        let bar = NSRect(x: art.minX, y: barY, width: art.width, height: barH)
        ctx.saveGState()
        squircle(art).addClip()
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.09).setFill()
        bar.fill()
        ctx.restoreGState()

        let lit = NSPoint(x: art.maxX - art.width * 0.22, y: bar.midY)
        glow(at: lit, radius: art.width * 0.46, colour: amber, ctx: ctx)
        amber.setFill()
        let d2 = barH * (simplified ? 0.70 : 0.58)
        NSBezierPath(ovalIn: NSRect(x: lit.x - d2 / 2, y: lit.y - d2 / 2, width: d2, height: d2)).fill()

    default: break
    }
    ctx.restoreGState()

    // A hairline highlight along the top edge, the way macOS icons catch light.
    NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14).setStroke()
    let edge = squircle(art.insetBy(dx: side * 0.004, dy: side * 0.004))
    edge.lineWidth = side * 0.008
    edge.stroke()
}

func image(variant: String, side: CGFloat, scale: CGFloat = 2) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                              pixelsWide: Int(side * scale), pixelsHigh: Int(side * scale),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = g
    g.cgContext.clear(CGRect(x: 0, y: 0, width: side * scale, height: side * scale))
    render(variant: variant, side: side, ctx: g.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

if variant == "sheet" {
    // A contact sheet: each variant big, then the sizes that actually decide whether an
    // icon works — 32 and 16. An icon that only looks good at 1024 is not an icon.
    let variants = ["strip", "aura"]
    let big: CGFloat = 220, pad: CGFloat = 26
    let w = pad + (big + pad) * CGFloat(variants.count)
    let h = pad + big + 34 + 58 + pad
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * 2), pixelsHigh: Int(h * 2),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
    NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: w, height: h).fill()
    for (i, v) in variants.enumerated() {
        let x = pad + (big + pad) * CGFloat(i)
        let yBig = h - pad - big
        // 直接畫進目前的 context。先前包了一層 `NSImage.lockFocus()`，那會把繪製導去
        // 另一個 context，大圖完全沒有進到這張表上——而表看起來還是「有東西」，
        // 只是少了最重要的那一欄。
        NSImage(cgImage: image(variant: v, side: big).cgImage!, size: NSSize(width: big, height: big))
            .draw(in: NSRect(x: x, y: yBig, width: big, height: big))
        let label = NSAttributedString(string: v, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor(srgbRed: 0.2, green: 0.2, blue: 0.22, alpha: 1)])
        label.draw(at: NSPoint(x: x, y: yBig - 24))
        // real 32 and 16, drawn at their own size then shown 1:1 and 2:1
        var sx = x
        for s in [CGFloat(32), 16] {
            let im = NSImage(cgImage: image(variant: v, side: s).cgImage!,
                             size: NSSize(width: s, height: s))
            im.draw(in: NSRect(x: sx, y: yBig - 70, width: s, height: s))
            im.draw(in: NSRect(x: sx + s + 8, y: yBig - 70, width: s * 2, height: s * 2))
            sx += s * 3 + 26
        }
        let cap = NSAttributedString(string: "32pt / ×2      16pt / ×2", attributes: [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor(srgbRed: 0.45, green: 0.45, blue: 0.47, alpha: 1)])
        cap.draw(at: NSPoint(x: x, y: yBig - 88))
    }
    NSGraphicsContext.restoreGraphicsState()
    write(rep, out)
} else {
    write(image(variant: variant, side: requested, scale: scaleArg), out)
}
print("wrote \(out)")
