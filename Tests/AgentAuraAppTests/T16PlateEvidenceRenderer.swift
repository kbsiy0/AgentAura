import AppKit
import Foundation
import Testing
import AuraCore
@testable import AgentAuraApp

/// T16：驗收證據——底板開／關 × 深／淺選單列，四張圖，燈條放大到看得清楚四邊是否真的對稱。
/// 沿用 `EvidenceRenderer` 的合成手法（真 view + 模擬 bar 背景），輸出到
/// `docs/evidence/phase2/`（這個 change 累加證據圖的既有位置，見 `Phase2EvidenceRenderer`）。
@MainActor
@Suite("T16 燈條底板開關證據圖（env gate）",
      .enabled(if: ProcessInfo.processInfo.environment["AURA_RENDER_EVIDENCE"] == "1"))
struct T16PlateEvidenceRenderer {

    static func outputDirectory() throws -> URL {
        try EvidenceRenderer.outputDirectory().deletingLastPathComponent().appendingPathComponent("phase2")
    }

    /// 放大倍率：LED 底板只有 44×18pt，不放大肉眼看不清楚四邊邊距是否對稱。
    static let magnify: CGFloat = 8

    static func renderMagnified(showsPlate: Bool, bar: EvidenceRenderer.Bar) throws -> CGImage {
        let view = LEDStripView()
        view.frame = NSRect(x: 0, y: 0, width: LEDStripView.preferredWidth, height: LEDStripView.plateHeight)
        view.setShowsPlate(showsPlate)
        let icon = IconState(activity: .working, counts: [.working: 1], liveCount: 1)
        view.update(AppearancePolicy.appearance(for: icon, reduceMotion: true), phase: 0)

        let pad: CGFloat = 6
        let width = view.frame.width + pad * 2, height = view.frame.height + pad * 2
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: Int(width * Self.magnify), height: Int(height * Self.magnify),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw OffscreenRender.SampleError.contextCreationFailed }
        ctx.scaleBy(x: Self.magnify, y: Self.magnify)
        ctx.setFillColor(red: bar.fill.0, green: bar.fill.1, blue: bar.fill.2, alpha: 1)   // 不透明底，放大圖不必模擬材質
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        ctx.saveGState()
        ctx.translateBy(x: pad, y: pad)
        view.displayIgnoringOpacity(view.bounds, in: ns)
        ctx.restoreGState()
        guard let image = ctx.makeImage() else { throw OffscreenRender.SampleError.noData }
        return image
    }

    @Test("產出 4 張：底板 開／關 × 深／淺選單列（放大 8×）")
    func renderPlateToggleEvidence() throws {
        let dir = try Self.outputDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var written = 0
        for bar in EvidenceRenderer.bars {
            for (label, showsPlate) in [("on", true), ("off", false)] {
                let image = try Self.renderMagnified(showsPlate: showsPlate, bar: bar)
                let url = dir.appendingPathComponent("T16-plate-\(label)-\(bar.name).png")
                try EvidenceRenderer.writePNG(image, to: url)
                written += 1
            }
        }
        #expect(written == 4, "應寫出 4 張（開／關 × 深／淺 bar），實際 \(written)")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("T16-plate-on-dark.png").path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("T16-plate-off-light.png").path))
    }
}
