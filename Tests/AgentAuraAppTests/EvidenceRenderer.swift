import AppKit
import Foundation
import Testing
import AuraCore
@testable import AgentAuraApp

/// spec `2026-09-09-m4-icon-form-design.md` §4.4 E1′、§6「Evidence renderer」。
/// 獨立成檔——避免與 `RendererPixelTests.swift` 撞 300 行上限。
///
/// T01 放骨架（env gate + 輸出路徑）；T07 補產圖：每張圖是一條模擬 menu bar，同時擺 5 態 × {靜態, 峰值}
/// 共 10 格（靜態 = reduceMotion 的真實樣貌），A2（贏家）× 深/淺 bar × 藍/暖/灰桌布 = 6 張 + 6 張 0.5× 遠距縮圖，
/// 共 12 張。**模擬不了**真實 backdrop blur／vibrancy——所以它是 E1 的補充，不是替代（spec §4.4）。
/// B2 已隨 T09 淘汰（`docs/2026-09-09-m4-ab-decision.md`），既有 `E1p-B2-*.png` 保留在 `docs/evidence/m4/`
/// 作為決策證據，不因這裡不再產出而刪除。
@MainActor
@Suite("Evidence renderer（E1′，env gate）",
      .enabled(if: ProcessInfo.processInfo.environment["AURA_RENDER_EVIDENCE"] == "1"))
struct EvidenceRenderer {

    enum PathError: Error, CustomStringConvertible {
        case repoRootNotFound(from: String)
        var description: String {
            switch self {
            case .repoRootNotFound(let from): return "從 \(from) 往上找不到 Package.swift —— 找不到 repo root"
            }
        }
    }

    /// 輸出目錄：由 `#filePath` 推到 repo root 的 `docs/evidence/m4/`。拒絕寫到 repo 外。
    /// 自成一體（不依賴 `AuraCoreTests` 的 `Gate`——那是另一個 test target，這裡看不到）。
    static func outputDirectory(sourceFile: String = #filePath) throws -> URL {
        var dir = URL(fileURLWithPath: sourceFile).deletingLastPathComponent()
        while true {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir.appendingPathComponent("docs/evidence/m4")
            }
            let parent = dir.deletingLastPathComponent()
            guard parent.path != dir.path else { throw PathError.repoRootNotFound(from: sourceFile) }
            dir = parent
        }
    }

    @Test("輸出路徑落在 repo 內的 docs/evidence/m4（骨架，T07 補產圖）")
    func outputPathStaysInRepo() throws {
        let dir = try Self.outputDirectory()
        #expect(dir.path.hasSuffix("docs/evidence/m4"), "輸出目錄應為 docs/evidence/m4，實際 \(dir.path)")
        // docs/evidence/m4 → 脫三層才是 repo root（review-t01-0203 B1：原本只脫兩層，開 env gate 就紅）
        let repoRoot = dir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        #expect(FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("Package.swift").path), """
            輸出目錄的祖先路徑（\(repoRoot.path)）對不到含 Package.swift 的 repo root —— 可能跑到 repo 外面了。
            """)
    }

    // MARK: - E1′ 產圖

    struct Bar { let name: String; let fill: (Double, Double, Double, Double) }
    struct Wall { let name: String; let from: (Double, Double, Double); let to: (Double, Double, Double) }
    static let bars = [Bar(name: "dark", fill: (28/255, 28/255, 30/255, 0.62)),
                       Bar(name: "light", fill: (250/255, 250/255, 252/255, 0.70))]
    static let walls = [Wall(name: "blue", from: (31/255, 78/255, 154/255), to: (74/255, 143/255, 224/255)),
                        Wall(name: "warm", from: (184/255, 92/255, 56/255), to: (232/255, 201/255, 160/255)),
                        Wall(name: "grey", from: (58/255, 58/255, 60/255), to: (110/255, 110/255, 115/255))]
    static let barHeight: CGFloat = 22
    static let gap: CGFloat = 14

    /// 10 格：5 態各一個靜態（reduceMotion）＋一個動畫峰值。
    static func slots() -> [(label: String, appearance: IconAppearance, phase: Double)] {
        Activity.allCases.sorted { $0.priority < $1.priority }.flatMap { a -> [(String, IconAppearance, Double)] in
            let icon = IconState(activity: a, counts: [a: 1], liveCount: 1)
            let s = AppearancePolicy.appearance(for: icon, reduceMotion: true)
            let d = AppearancePolicy.appearance(for: icon, reduceMotion: false)
            return [("\(a) 靜態", s, 0), ("\(a) 峰值", d, OffscreenRender.peakPhase(of: d.animation))]
        }
    }

    /// 畫一條模擬 bar：桌布漸層 → 半透明 bar → 10 個 icon 格 → 右側兩個假系統 glyph。回 CGImage（@2x）。
    @MainActor
    static func renderSheet(view: NSView & IconDrawing, bar: Bar, wall: Wall) throws -> CGImage {
        let slots = slots()
        let w = view.preferredWidth
        let width = 12 + CGFloat(slots.count) * (w + gap) + 60
        let scale: CGFloat = 2
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: Int(width * scale), height: Int(barHeight * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw OffscreenRender.SampleError.contextCreationFailed }
        ctx.scaleBy(x: scale, y: scale)
        let colors = [CGColor(colorSpace: cs, components: [wall.from.0, wall.from.1, wall.from.2, 1])!,
                      CGColor(colorSpace: cs, components: [wall.to.0, wall.to.1, wall.to.2, 1])!] as CFArray
        if let g = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: width, y: barHeight), options: [])
        }
        ctx.setFillColor(red: bar.fill.0, green: bar.fill.1, blue: bar.fill.2, alpha: bar.fill.3)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: barHeight))
        // 假系統 glyph（兩塊 label 色圓角矩形），給「協調度」一個參照
        let label: CGFloat = bar.name == "dark" ? 0.9 : 0.15
        ctx.setFillColor(red: label, green: label, blue: label, alpha: 0.85)
        for x in [width - 52, width - 28] {
            ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: 6, width: 16, height: 10), cornerWidth: 2, cornerHeight: 2, transform: nil))
            ctx.fillPath()
        }
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        for (i, slot) in slots.enumerated() {
            view.update(slot.appearance, phase: slot.phase)
            ctx.saveGState()
            ctx.translateBy(x: 12 + CGFloat(i) * (w + gap), y: 0)
            view.displayIgnoringOpacity(view.bounds, in: ns)
            ctx.restoreGState()
        }
        guard let image = ctx.makeImage() else { throw OffscreenRender.SampleError.noData }
        return image
    }

    static func writePNG(_ image: CGImage, to url: URL, scale: CGFloat = 1) throws {
        var out = image
        if scale != 1 {
            let w = Int(CGFloat(image.width) * scale), h = Int(CGFloat(image.height) * scale)
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: image.colorSpace!, bitmapInfo: image.bitmapInfo.rawValue)
            else { throw OffscreenRender.SampleError.contextCreationFailed }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            out = ctx.makeImage()!
        }
        let rep = NSBitmapImageRep(cgImage: out)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw OffscreenRender.SampleError.noData }
        try png.write(to: url)
    }

    @MainActor
    @Test("產出 E1′ 合成圖：A2 × 深/淺 bar × 三桌布（各 10 格）＋ 0.5× 縮圖 ＋ index.html（B2 既有圖只列不重產）")
    func renderEvidence() throws {
        let dir = try Self.outputDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var html = "<!doctype html><meta charset=utf-8><title>E1′ 合成圖</title><style>body{font:13px -apple-system,system-ui;padding:20px;background:#f5f5f7;color:#1d1d1f}img{display:block;margin:4px 0 12px;image-rendering:auto}h2{margin-top:28px}.cap{color:#6e6e73;font-size:11px}</style><h1>E1′ 離屏合成圖（真 view、模擬背景）</h1><p class=cap>每條 bar 10 格，依優先序：idle／done／working／waiting／error，各「靜態（= reduceMotion 樣貌）」與「動畫峰值」。模擬不了真實 backdrop blur，對比／顏色維度以 E1 為準。</p>\n"
        var written = 0
        for (form, make) in [("A2", { () -> NSView & IconDrawing in
                                  let v = LEDStripView(); v.frame = NSRect(x: 0, y: 0, width: v.preferredWidth, height: Self.barHeight); return v })] {
            html += "<h2>\(form)</h2>\n"
            for bar in Self.bars {
                for wall in Self.walls {
                    let image = try Self.renderSheet(view: make(), bar: bar, wall: wall)
                    let base = "E1p-\(form)-\(bar.name)-\(wall.name)"
                    try Self.writePNG(image, to: dir.appendingPathComponent("\(base).png"))
                    try Self.writePNG(image, to: dir.appendingPathComponent("\(base)-half.png"), scale: 0.5)
                    written += 2
                    html += "<div class=cap>\(base) — \(bar.name) bar · \(wall.name) 桌布（上：1×，下：0.5× 遠距）</div><img src=\"\(base).png\" width=\"\(image.width / 2)\"><img src=\"\(base)-half.png\" width=\"\(image.width / 4)\">\n"
                }
            }
        }
        // 出局形態的合成圖是決策證據（docs/2026-09-09-m4-ab-decision.md 引用），刻意保留在磁碟上；
        // 這裡只列出既有檔、不重新渲染——讓 index.html 重產是冪等的，也不會讓證據變成沒人引用的孤兒。
        let retired = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("E1p-B2-") && $0.hasSuffix(".png") && !$0.hasSuffix("-half.png") }.sorted()
        if !retired.isEmpty {
            html += "<h2>B2（出局，2026-09-09 A/B 決策證據，保留不重產）</h2>\n"
            for name in retired {
                let base = String(name.dropLast(4))
                html += "<div class=cap>\(base)</div><img src=\"\(base).png\"><img src=\"\(base)-half.png\">\n"
            }
        }
        try html.write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        #expect(written == 12, "應寫出 12 張 PNG（1 形態 × 2 bar × 3 桌布 × {1×, 0.5×}），實際 \(written)")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("E1p-A2-dark-blue.png").path))
    }
}
