import AppKit
import Foundation
import SwiftUI
import Testing
import AuraCore
@testable import AgentAuraApp

/// T19：白色 working 落地後的驗收證據圖——面板圖例／單列色點（white-on-white 風險，配套 B
/// 的 `DotRing` 是否保它看得見）＋ menu bar 燈條（配套 A 的白色本身，沿用 T16 的放大手法）。
/// 輸出到 `docs/evidence/phase2/`（Change 2 既有那批沿用的位置，見 `T16PlateEvidenceRenderer`）。
@MainActor
@Suite("T19 白色 working 證據圖（env gate）",
      .enabled(if: ProcessInfo.processInfo.environment["AURA_RENDER_EVIDENCE"] == "1"))
struct T19WhiteWorkingEvidenceRenderer {

    static func outputDirectory() throws -> URL {
        try EvidenceRenderer.outputDirectory().deletingLastPathComponent().appendingPathComponent("phase2")
    }

    func session(_ id: String, _ a: Activity) -> SessionState {
        SessionState(id: id, projectName: id,
                    permissionMode: nil, effort: nil, model: nil,
                    activity: a, mainActivity: a, subActivity: nil,
                    currentTool: "Bash", subagentTool: nil, toolDurationMs: nil,
                    turnStartedAt: nil, subagents: [:], toolFailures: 0,
                    lastMessage: nil, errorType: nil, toolError: nil,
                    liveness: .alive(pid: 1), updatedAt: Date())
    }

    // 面板卡片背景近似值，沿用 `VisualLandedEvidenceRenderer` 同一組（可逐張比對）。
    static let lightBg = NSColor(srgbRed: 0xf2 / 255, green: 0xf2 / 255, blue: 0xf7 / 255, alpha: 1)
    static let darkBg = NSColor(srgbRed: 0x1c / 255, green: 0x1c / 255, blue: 0x1e / 255, alpha: 1)

    func renderPanelSlice(_ view: some View, over background: NSColor, appearance: NSAppearance.Name,
                          size: NSSize) throws -> CGImage {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: appearance)
        hosting.frame = NSRect(origin: .zero, size: size)
        let bitmap = try OffscreenRender.render(hosting, over: background)
        guard let image = bitmap.context.makeImage() else { throw OffscreenRender.SampleError.noData }
        return image
    }

    @Test("產出 6 張：{legend,row,menubar} × {light,dark}")
    func renderWhiteWorkingEvidence() throws {
        let dir = try Self.outputDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var written = 0

        // (a)(b) 圖例／單列——白色 working 在面板卡片背景上，DotRing 保不保得住看得見（放大 4×，
        // 10pt／8pt 色點在原尺寸肉眼不好判斷邊線）。
        let legend = LegendModel.items(for: .default)
        let row = try #require(PanelViewModel.rows(from: [session("a", .working)]).first)
        let scenarios: [(name: String, view: AnyView, size: NSSize)] = [
            ("legend", AnyView(LegendRowView(legend: legend, onAction: { _ in })), NSSize(width: 380, height: 24)),
            ("row", AnyView(PanelRowView(row: row, palette: .default)), NSSize(width: 380, height: 30)),
        ]
        for scenario in scenarios {
            let light = try renderPanelSlice(scenario.view, over: Self.lightBg, appearance: .aqua, size: scenario.size)
            try EvidenceRenderer.writePNG(light, to: dir.appendingPathComponent("T19-white-\(scenario.name)-light.png"), scale: 4)
            let dark = try renderPanelSlice(scenario.view, over: Self.darkBg, appearance: .darkAqua, size: scenario.size)
            try EvidenceRenderer.writePNG(dark, to: dir.appendingPathComponent("T19-white-\(scenario.name)-dark.png"), scale: 4)
            written += 2
        }

        // (c) menu bar 燈條——沿用 T16 的放大手法（底板開、working 靜態，見 `T16PlateEvidenceRenderer`）。
        for bar in EvidenceRenderer.bars {
            let image = try T16PlateEvidenceRenderer.renderMagnified(showsPlate: true, bar: bar)
            try EvidenceRenderer.writePNG(image, to: dir.appendingPathComponent("T19-white-menubar-\(bar.name).png"))
            written += 1
        }

        #expect(written == 6, "應寫出 6 張（legend／row／menubar × 深淺），實際 \(written)")
    }
}
