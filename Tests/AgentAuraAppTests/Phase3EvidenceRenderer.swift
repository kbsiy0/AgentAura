import AppKit
import Foundation
import SwiftUI
import Testing
import AuraCore
@testable import AgentAuraApp

/// T12（phase 2 B 波，B1–B5）：team-lead 要肉眼看的證據圖，沿用 `Phase2EvidenceRenderer`
/// 同一套輸出目錄／`renderPair`／`rebuildIndex`（`docs/evidence/phase2/`，B1…B5 前綴）。
///
/// **B1／B2／B4 共用一張圖**：右鍵（B1）與 footer「Options ⌄」左鍵走的是同一個
/// `optionsExpanded == true` 面板狀態，視覺上完全一樣（差異只在觸發手勢，由
/// `RightClickOpensOptionsTests` 守，不是像素能證明的事）；「回報問題…」（B2）與
/// 「關於 AgentAura」（B4）都只是這份展開列表裡的新增列，同一張圖就看得到兩個都在。
/// **B3 沒有對應畫面**：⌘Q 監聽器不是視覺元件，證據是 `QuitKeyMonitorTests` 的 gate 輸出。
@MainActor
@Suite("Phase 2 B 波修復證據圖（env gate）",
      .enabled(if: ProcessInfo.processInfo.environment["AURA_RENDER_EVIDENCE"] == "1"))
struct Phase3EvidenceRenderer {

    func render(_ model: PanelModel, over background: NSColor, appearance: NSAppearance.Name) throws -> CGImage {
        let hosting = NSHostingView(rootView: PanelView(model: model, onAction: { _ in }))
        hosting.appearance = NSAppearance(named: appearance)
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(hosting.fittingSize.height, 44))
        let bitmap = try OffscreenRender.render(hosting, over: background)
        guard let image = bitmap.context.makeImage() else { throw OffscreenRender.SampleError.noData }
        return image
    }

    /// B1／B2／B4：展開的 Options 列表——右鍵（B1）走到這裡；「回報問題…」（B2）與
    /// 「關於 AgentAura」（B4）都是列表裡看得到的新列。
    @Test("B1/B2/B4：展開的 Options 列表含「回報問題…」與「關於 AgentAura」")
    func renderB1B2B4Evidence() throws {
        let dir = try Phase2EvidenceRenderer.outputDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let model = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                    install: .connected(owner: .thisApp, verified: .verified), version: "0.1.0",
                                    optionsExpanded: true, launchAtLogin: true, externalTargetPath: nil, banner: nil,
                                    systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese, codex: .unavailable, codexSnippet: nil, codexPathRejection: nil)
        try Phase2EvidenceRenderer.renderPair(dir: dir, name: "B1-B2-B4-options-expanded", model: model, render: render)
        try Phase2EvidenceRenderer.rebuildIndex(dir: dir)
    }

    /// B5：「減少動態」列的兩種可見狀態——系統沒強制時可自由切換（開）；系統強制時
    /// 開＋disabled＋灰字說明「系統設定已開啟」（否則會出現「開關說關、動畫卻不動」）。
    @Test("B5：減少動態列——使用者自行開啟／系統強制（disabled ＋ 說明文字）")
    func renderB5Evidence() throws {
        let dir = try Phase2EvidenceRenderer.outputDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let userOn = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                     install: .connected(owner: .thisApp, verified: .verified), version: "0.1.0",
                                     optionsExpanded: true, launchAtLogin: true, externalTargetPath: nil, banner: nil,
                                     systemReduceMotion: false, userReduceMotion: true, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese, codex: .unavailable, codexSnippet: nil, codexPathRejection: nil)
        try Phase2EvidenceRenderer.renderPair(dir: dir, name: "B5-reduceMotion-userOn", model: userOn, render: render)

        let systemForced = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                           install: .connected(owner: .thisApp, verified: .verified), version: "0.1.0",
                                           optionsExpanded: true, launchAtLogin: true, externalTargetPath: nil, banner: nil,
                                           systemReduceMotion: true, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese, codex: .unavailable, codexSnippet: nil, codexPathRejection: nil)
        try Phase2EvidenceRenderer.renderPair(dir: dir, name: "B5-reduceMotion-systemForced", model: systemForced, render: render)

        try Phase2EvidenceRenderer.rebuildIndex(dir: dir)
    }

    /// C1：分隔線分組前後對照——「before」重用 `OptionsDividerGroupingPixelTests.AllDividersLayout`
    /// （舊行為的最小重現：每列後面都有一條 `Divider`），「after」是真的 production
    /// `OptionsSectionView`（只在群組交界畫線）。
    @Test("C1：分隔線分組前後對照（每列都隔開 vs 只在群組交界）")
    func renderC1Evidence() throws {
        let dir = try Phase2EvidenceRenderer.outputDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let model = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                    install: .connected(owner: .external, verified: .unknown), version: "0.1.0",
                                    optionsExpanded: true, launchAtLogin: true,
                                    externalTargetPath: "/Users/dev/repo/plugin", banner: nil,
                                    systemReduceMotion: true, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese, codex: .unavailable, codexSnippet: nil, codexPathRejection: nil)
        // T07：PanelModel 還沒有 codex 欄位（T08 才加），先傳 .unavailable/nil。
        let rows = OptionsMenuModel.rows(install: model.install, launchAtLogin: model.launchAtLogin,
                                         isDefaultPalette: model.isDefaultPalette,
                                         systemReduceMotion: model.systemReduceMotion,
                                         userReduceMotion: model.userReduceMotion, iconPlate: model.iconPlate, iconShape: .ledStrip, palette: model.palette, language: .traditionalChinese,
                                         codex: .unavailable, codexPathRejection: nil)

        func renderView(_ view: some View, over background: NSColor, appearance: NSAppearance.Name) throws -> CGImage {
            let hosting = NSHostingView(rootView: view)
            hosting.appearance = NSAppearance(named: appearance)
            hosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(hosting.fittingSize.height, 44))
            let bitmap = try OffscreenRender.render(hosting, over: background)
            guard let image = bitmap.context.makeImage() else { throw OffscreenRender.SampleError.noData }
            return image
        }

        let dark = NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)
        let before = OptionsDividerGroupingPixelTests.AllDividersLayout(rows: rows, onAction: { _ in })
        try EvidenceRenderer.writePNG(try renderView(before, over: .white, appearance: .aqua),
                                      to: dir.appendingPathComponent("C1-before-allDividers-light.png"))
        try EvidenceRenderer.writePNG(try renderView(before, over: dark, appearance: .darkAqua),
                                      to: dir.appendingPathComponent("C1-before-allDividers-dark.png"))

        let after = OptionsSectionView(model: model, onAction: { _ in })
        try EvidenceRenderer.writePNG(try renderView(after, over: .white, appearance: .aqua),
                                      to: dir.appendingPathComponent("C1-after-grouped-light.png"))
        try EvidenceRenderer.writePNG(try renderView(after, over: dark, appearance: .darkAqua),
                                      to: dir.appendingPathComponent("C1-after-grouped-dark.png"))

        try Phase2EvidenceRenderer.rebuildIndex(dir: dir)
    }
}
