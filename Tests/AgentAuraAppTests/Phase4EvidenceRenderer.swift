import AppKit
import Foundation
import SwiftUI
import Testing
import AuraCore
@testable import AgentAuraApp

/// T13（persona 重測收尾批次）：沿用 `Phase2EvidenceRenderer` 同一套輸出目錄／`renderPair`／
/// `rebuildIndex`（`docs/evidence/phase2/`，`T13-*` 前綴，跟 A／B 波的舊檔分開好找）。
///
/// S1-3／S1-4'（用語、減少動態的可及性提醒）與 S1-4 PARTIAL（術語統一）不需要新測試碼——
/// 重跑既有的 `Phase2EvidenceRenderer`／`Phase3EvidenceRenderer`（`A2-broken-title`／
/// `B5-reduceMotion-*`）就會用現在的生產碼重新渲染，字面自動反映修好之後的樣子。
/// 這裡只補 S1-1 專屬的一張——team-lead 要看的「非 connected 面板不再三行同句、
/// 處方在按鈕之前就看得到」。
@MainActor
@Suite("T13 收尾證據圖（env gate）",
      .enabled(if: ProcessInfo.processInfo.environment["AURA_RENDER_EVIDENCE"] == "1"))
struct Phase4EvidenceRenderer {

    func render(_ model: PanelModel, over background: NSColor, appearance: NSAppearance.Name) throws -> CGImage {
        let hosting = NSHostingView(rootView: PanelView(model: model, onAction: { _ in }))
        hosting.appearance = NSAppearance(named: appearance)
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(hosting.fittingSize.height, 44))
        let bitmap = try OffscreenRender.render(hosting, over: background)
        guard let image = bitmap.context.makeImage() else { throw OffscreenRender.SampleError.noData }
        return image
    }

    /// S1-1：與 `Phase2EvidenceRenderer.renderA2Evidence` 同一個 `.broken(.hookBlockedOrBroken,
    /// owner: .thisApp)` 狀態——修前六行裡三行同句（標題／本體標題／chip 都印 healthLabel），
    /// 處方（「把 App 拖進「應用程式」…」）只有按下「接上」失敗之後才看得到。修後：標題只在
    /// 頂端出現一次，本體改印處方（`explanationDetail`，按鈕之前就看得到）。
    @Test("T13-S1-1：非 connected 落地頁——標題不再三次同句，處方在按鈕之前就看得到")
    func renderS11Evidence() throws {
        let dir = try Phase2EvidenceRenderer.outputDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let hookBlocked = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                          install: .broken(.hookBlockedOrBroken, owner: .thisApp), version: "1.0",
                                          optionsExpanded: false, launchAtLogin: nil, externalTargetPath: nil,
                                          banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese, codex: .unavailable, codexSnippet: nil)
        try Phase2EvidenceRenderer.renderPair(dir: dir, name: "T13-S1-1-hookBlocked-prescription-before-press",
                                              model: hookBlocked, render: render)

        // 對照：5 個「按接上就會重建修好」的結構性 reason 之一（targetMissing），確認它們
        // 也有非空處方，不是只有 hookBlockedOrBroken 這個特例。
        let targetMissing = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                            install: .broken(.targetMissing, owner: .thisApp), version: "1.0",
                                            optionsExpanded: false, launchAtLogin: nil, externalTargetPath: nil,
                                            banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese, codex: .unavailable, codexSnippet: nil)
        try Phase2EvidenceRenderer.renderPair(dir: dir, name: "T13-S1-1-targetMissing-prescription",
                                              model: targetMissing, render: render)

        try Phase2EvidenceRenderer.rebuildIndex(dir: dir)
    }
}
