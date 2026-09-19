import AppKit
import Foundation
import SwiftUI
import Testing
import AuraCore
@testable import AgentAuraApp

/// T15（app-shell）：V1 落地後的「原型 vs 落地」對照——渲**生產** `PanelView`（不是任何原型），
/// 檔名沿用 `docs/superpowers/specs/2026-09-11-panel-visual-ab.md` §3 的檔名慣例
/// （`V1-{sessions,notConnected}-{light,dark}.png`），加 `-landed` 供 team-lead 跟
/// `docs/evidence/design-ab/V1-*.png`（原型渲圖，決策證據，保留不覆蓋）逐張比對。
/// 沿用既有 `EvidenceRenderer`／`Phase2EvidenceRenderer` 的模式（env gate，`NSHostingView`
/// ＋ `OffscreenRender`，不是 `ImageRenderer`）——不是新的一套。
@MainActor
@Suite("V1 落地對照證據圖（T15，env gate）",
      .enabled(if: ProcessInfo.processInfo.environment["AURA_RENDER_EVIDENCE"] == "1"))
struct VisualLandedEvidenceRenderer {

    static func outputDirectory() throws -> URL {
        try EvidenceRenderer.outputDirectory().deletingLastPathComponent().appendingPathComponent("design-ab")
    }

    func session(_ id: String, _ name: String, _ a: Activity, tool: String? = "Bash",
                subagentTool: String? = nil, turnStartedAt: Date? = nil, subagents: [String: Int] = [:],
                toolDescription: String? = nil, lastMessage: String? = nil,
                liveness: Liveness = .alive(pid: 1), updatedAt: Date) -> SessionState {
        SessionState(id: id, projectName: name,
                    permissionMode: "default", effort: "high", model: "claude-opus-5",
                    activity: a, mainActivity: a, subActivity: subagentTool == nil ? nil : .working,
                    currentTool: tool, subagentTool: subagentTool, toolDurationMs: nil,
                    turnStartedAt: turnStartedAt, subagents: subagents, toolFailures: 0,
                    lastMessage: lastMessage, errorType: nil, toolError: nil,
                    toolDescription: toolDescription, notificationMessage: nil,
                    liveness: liveness, updatedAt: updatedAt)
    }

    /// 狀態 A：與已刪除的 `VisualVariantFixtures.stateASessions` 同一組資料（waiting／working／
    /// 已結束的 done），只是不再經原型型別，直接餵生產 `PanelModel.make`。
    func stateAModel() -> PanelModel {
        let now = Date()
        let sessions = [
            session("fitness-tracker", "fitness-tracker", .waiting, toolDescription: "覆寫 ~/.claude/settings.json", updatedAt: now.addingTimeInterval(-8)),
            session("payments-api", "payments-api", .working, tool: "Edit", subagentTool: "Explore → Grep",
                    turnStartedAt: now.addingTimeInterval(-380), subagents: ["explore": 2], updatedAt: now.addingTimeInterval(-3)),
            session("Nightly", "Nightly", .done, tool: nil, lastMessage: "產出落地後的對照證據圖。",
                   liveness: .ended, updatedAt: now.addingTimeInterval(-900)),
        ]
        var counts: [Activity: Int] = [:]
        for s in sessions { counts[s.activity, default: 0] += 1 }
        let icon = IconState(activity: sessions.map(\.activity).max() ?? .idle, counts: counts, liveCount: 2)
        return PanelModel.make(icon: icon, sessions: sessions, palette: .default,
                               install: .connected(owner: .thisApp, verified: .verified), version: "1.4.2",
                               optionsExpanded: true, launchAtLogin: true, externalTargetPath: nil, banner: nil,
                               systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese, codex: .unavailable, codexSnippet: nil, codexPathRejection: nil, now: now)
    }

    func stateBModel() -> PanelModel {
        PanelModel.make(icon: .empty, sessions: [], palette: .default,
                        install: .broken(.hookBlockedOrBroken, owner: .thisApp), version: "1.4.2",
                        optionsExpanded: false, launchAtLogin: true, externalTargetPath: nil, banner: nil,
                        systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese, codex: .unavailable, codexSnippet: nil, codexPathRejection: nil)
    }

    func render(_ model: PanelModel, over background: NSColor, appearance: NSAppearance.Name) throws -> CGImage {
        let hosting = NSHostingView(rootView: PanelView(model: model, onAction: { _ in }))
        hosting.appearance = NSAppearance(named: appearance)
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(hosting.fittingSize.height, 44))
        let bitmap = try OffscreenRender.render(hosting, over: background)
        guard let image = bitmap.context.makeImage() else { throw OffscreenRender.SampleError.noData }
        return image
    }

    @Test("渲 4 張（{sessions, notConnected} × 深淺）＋ 附加進 design-ab/index.html")
    func renderLanded() throws {
        let dir = try Self.outputDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // §4 的代表性底色（跟原型渲圖同一組，才能逐張比對）。
        let lightBg = NSColor(srgbRed: 0xf2 / 255, green: 0xf2 / 255, blue: 0xf7 / 255, alpha: 1)
        let darkBg = NSColor(srgbRed: 0x1c / 255, green: 0x1c / 255, blue: 0x1e / 255, alpha: 1)

        let scenarios: [(key: String, model: PanelModel)] = [
            ("sessions", stateAModel()),
            ("notConnected", stateBModel()),
        ]
        var written = 0
        for scenario in scenarios {
            let light = try render(scenario.model, over: lightBg, appearance: .aqua)
            try EvidenceRenderer.writePNG(light, to: dir.appendingPathComponent("V1-landed-\(scenario.key)-light.png"))
            let dark = try render(scenario.model, over: darkBg, appearance: .darkAqua)
            try EvidenceRenderer.writePNG(dark, to: dir.appendingPathComponent("V1-landed-\(scenario.key)-dark.png"))
            written += 2
        }
        #expect(written == 4, "應寫出 4 張（2 內容狀態 × 深淺），實際 \(written)")
    }
}
