#!/usr/bin/env swift
// Draws the background image for the .dmg installer window.
//
//   swift scripts/dmg-background.swift out.png
//
// AppKit rather than ImageMagick: the text is bilingual and ImageMagick on this machine
// can't read PingFang.ttc, so Chinese came out as empty boxes. AppKit renders both scripts
// correctly without any font wrangling.
//
// The second half of this image is the important half. The app is ad-hoc signed and not
// notarized, so the first launch *will* be blocked, and the dialog macOS shows has
// "Move to Trash" as its most prominent button. Someone who hasn't been warned will click it.
// Telling them before they get there is the whole point.

import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"

let size = NSSize(width: 640, height: 420)
let scale: CGFloat = 2

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
    fatalError("couldn't allocate the bitmap")
}
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// ---- palette. Light, quiet, close to a stock Finder window.
let bg      = NSColor(srgbRed: 0.965, green: 0.965, blue: 0.970, alpha: 1)
let ink     = NSColor(srgbRed: 0.114, green: 0.114, blue: 0.125, alpha: 1)
let muted   = NSColor(srgbRed: 0.431, green: 0.431, blue: 0.451, alpha: 1)
let accent  = NSColor(srgbRed: 0.000, green: 0.478, blue: 1.000, alpha: 1)
let warnBG  = NSColor(srgbRed: 1.000, green: 0.953, blue: 0.890, alpha: 1)
let warnInk = NSColor(srgbRed: 0.478, green: 0.310, blue: 0.000, alpha: 1)

bg.setFill()
NSRect(origin: .zero, size: size).fill()

func font(_ s: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont { .systemFont(ofSize: s, weight: w) }

/// y is measured from the TOP, which is how the rest of this file thinks about the window.
func draw(_ text: String, _ f: NSFont, _ colour: NSColor, centreX: CGFloat, top: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: colour]
    let s = NSAttributedString(string: text, attributes: attrs)
    let w = s.size().width
    s.draw(at: NSPoint(x: centreX - w / 2, y: size.height - top - s.size().height))
}

// ---- step 1: drag. The icons themselves are placed by the AppleScript in make-dmg.sh;
// this only draws the words and the arrow between where they will land.
draw("AgentAura", font(26, .semibold), ink, centreX: 320, top: 28)
draw("Drag the app onto the Applications folder",
     font(14), muted, centreX: 320, top: 64)
draw("把 App 拖到右邊的「應用程式」資料夾",
     font(13), muted, centreX: 320, top: 86)

// Arrow, sitting between the two icon slots at x = 160 and x = 480.
let arrowY: CGFloat = size.height - 195
let path = NSBezierPath()
path.move(to: NSPoint(x: 258, y: arrowY))
path.line(to: NSPoint(x: 372, y: arrowY))
path.lineWidth = 2.5
accent.setStroke()
path.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 386, y: arrowY))
head.line(to: NSPoint(x: 370, y: arrowY + 8))
head.line(to: NSPoint(x: 370, y: arrowY - 8))
head.close()
accent.setFill()
head.fill()

// ---- step 2: the part people get stuck on.
let boxTop: CGFloat = 268
let box = NSRect(x: 40, y: size.height - boxTop - 118, width: 560, height: 118)
warnBG.setFill()
NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()

draw("First time you open it, macOS will say it can't verify the app.",
     font(13, .semibold), warnInk, centreX: 320, top: boxTop + 16)
draw("Click Done — not \"Move to Trash\". Then open System Settings ▸ Privacy & Security,",
     font(12), warnInk, centreX: 320, top: boxTop + 38)
draw("scroll down and click \"Open Anyway\".",
     font(12), warnInk, centreX: 320, top: boxTop + 56)
draw("第一次開啟會跳出「無法驗證」。請按「完成」，不要按「移到垃圾桶」，",
     font(12), warnInk, centreX: 320, top: boxTop + 78)
draw("再到「系統設定 ▸ 隱私權與安全性」往下捲，按「強制打開」。",
     font(12), warnInk, centreX: 320, top: boxTop + 96)

draw("This happens because the app isn't notarized by Apple. It only happens once.",
     font(11), muted, centreX: 320, top: 396)

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fatalError("couldn't encode the PNG")
}
try! data.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
