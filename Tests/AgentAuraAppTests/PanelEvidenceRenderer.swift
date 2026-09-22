import AppKit
import Foundation
import SwiftUI
import Testing
import AuraCore
@testable import AgentAuraApp

/// spec `2026-09-09-panel-legend-palette-design.md` §6 `evidenceRenderer`：面板證據圖（persona T07 用）。
/// 走 `NSHostingView` + `OffscreenRender`（不是 `ImageRenderer`）；`AURA_RENDER_EVIDENCE=1` 才跑；
/// 輸出 `docs/evidence/change2/`；冪等。**背景是白／深灰的純色**，不是真實 popover 材質——
/// 圖例／列色點的顏色與版面可信，材質與 vibrancy 不可信；產圖機器的外觀寫進 index.html。
@MainActor
@Suite("面板證據圖（Change 2，env gate）",
      .enabled(if: ProcessInfo.processInfo.environment["AURA_RENDER_EVIDENCE"] == "1"))
struct PanelEvidenceRenderer {

    static func outputDirectory() throws -> URL {
        try EvidenceRenderer.outputDirectory().deletingLastPathComponent().appendingPathComponent("change2")
    }

    static let customPalette = IconPalette(
        idle:    IconPalette.default.idle,
        working: RGBA(r: 100/255, g: 180/255, b: 255/255, a: 1),   // 亮一點的藍（F-05 的常見自訂）
        done:    RGBA(r: 48/255,  g: 209/255, b: 88/255,  a: 1),
        waiting: RGBA(r: 255/255, g: 214/255, b: 10/255,  a: 1),   // 黃：與 done 亮度拉開（F-01 的能力示範）
        error:   RGBA(r: 255/255, g: 69/255,  b: 58/255,  a: 1))

    func session(_ id: String, _ a: Activity, tool: String, message: String? = nil) -> SessionState {
        SessionState(id: id, projectName: id,
                    permissionMode: "default", effort: "high", model: "claude-opus-5",
                    activity: a, mainActivity: a, subActivity: nil,
                    currentTool: tool, subagentTool: a == .working ? "Explore → Grep" : nil, toolDurationMs: nil,
                    turnStartedAt: Date().addingTimeInterval(-380), subagents: [:], toolFailures: 0,
                    lastMessage: message, errorType: a == .error ? "overloaded_error" : nil, toolError: nil,
                    liveness: .alive(pid: 1), updatedAt: Date().addingTimeInterval(-12))
    }

    /// 離屏 view 沒有 window，繪圖外觀會跟隨機器設定（實測 Dark 機器上淺底渲出白字疊白底）——
    /// 所以依背景**明確指定** `NSAppearance`，證據圖才有可讀的文字。
    func render(_ model: PanelModel, over background: NSColor, appearance: NSAppearance.Name) throws -> CGImage {
        let hosting = NSHostingView(rootView: PanelView(model: model, onAction: { _ in }))
        hosting.appearance = NSAppearance(named: appearance)
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(hosting.fittingSize.height, 44))
        let bitmap = try OffscreenRender.render(hosting, over: background)
        guard let image = bitmap.context.makeImage() else { throw OffscreenRender.SampleError.noData }
        return image
    }

    @Test("產出面板證據：預設 palette × {空, 三列}、自訂 palette × 三列，深淺背景各一，＋ index.html")
    func renderPanelEvidence() throws {
        let dir = try Self.outputDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let three = [session("payments-api", .working, tool: "Edit"),
                     session("fitness-tracker", .waiting, tool: "Bash"),
                     session("Nightly", .error, tool: "Bash", message: "overloaded")]
        let icon = IconState(activity: .error, counts: [.working: 1, .waiting: 1, .error: 1], liveCount: 3)
        let empty = IconState.empty
        let cases: [(String, PanelModel)] = [
            ("default-empty", PanelModel.make(icon: empty, sessions: [], palette: .default,
                                              install: .notConnected, version: "1.0", optionsExpanded: false,
                                              launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese, codex: .unavailable, codexSnippet: nil, codexPathRejection: nil)),
            ("default-3rows", PanelModel.make(icon: icon, sessions: three, palette: .default,
                                              install: .notConnected, version: "1.0", optionsExpanded: false,
                                              launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese, codex: .unavailable, codexSnippet: nil, codexPathRejection: nil)),
            ("custom-3rows", PanelModel.make(icon: icon, sessions: three, palette: Self.customPalette,
                                             install: .notConnected, version: "1.0", optionsExpanded: false,
                                             launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese, codex: .unavailable, codexSnippet: nil, codexPathRejection: nil)),
        ]
        let appearance = NSApp?.effectiveAppearance.name.rawValue ?? NSAppearance.currentDrawing().name.rawValue
        var html = "<!doctype html><meta charset=utf-8><title>Change 2 面板證據</title><style>body{font:13px -apple-system,system-ui;padding:20px;background:#f5f5f7;color:#1d1d1f}img{display:block;margin:4px 0 14px;border:1px solid #d2d2d7}.cap{color:#6e6e73;font-size:11px}</style><h1>Change 2 面板證據（NSHostingView 離屏）</h1><p class=cap>產圖外觀：淺底以 .aqua、深底以 .darkAqua 明確指定（機器外觀 \(appearance) 不影響）。背景為純色，非真實 popover 材質——版面與色點顏色可信，材質不可信。「重設」在預設 palette 下為 disabled（灰字）。</p>\n"
        var written = 0
        for (name, model) in cases {
            for (bg, bgName, look) in [(NSColor.white, "light", NSAppearance.Name.aqua),
                                       (NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1), "dark", NSAppearance.Name.darkAqua)] {
                let image = try render(model, over: bg, appearance: look)
                let file = "panel-\(name)-\(bgName).png"
                try EvidenceRenderer.writePNG(image, to: dir.appendingPathComponent(file))
                written += 1
                html += "<div class=cap>\(file)（\(image.width / 2)×\(image.height / 2) pt）</div><img src=\"\(file)\" width=\"\(image.width / 2)\">\n"
            }
        }
        try html.write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        #expect(written == 6, "應寫出 6 張（3 情境 × 深淺背景），實際 \(written)")
    }
}
