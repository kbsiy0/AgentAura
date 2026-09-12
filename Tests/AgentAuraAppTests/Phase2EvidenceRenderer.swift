import AppKit
import Foundation
import SwiftUI
import Testing
import AuraCore
@testable import AgentAuraApp

/// `docs/superpowers/plans/2026-09-10-phase2-ux-scope.md` A 波：team-lead 每條修完要肉眼看的
/// 證據圖。走 `PanelEvidenceRenderer` 同一套（`NSHostingView` + `OffscreenRender`，不是
/// `ImageRenderer`），輸出 `docs/evidence/phase2/`。**一個 change 內逐 commit 累加**——
/// 每次跑都重掃目錄現有 PNG 重建 `index.html`（冪等，不因為只跑其中一個 @Test 而漏列）。
@MainActor
@Suite("Phase 2 A 波修復證據圖（env gate）",
      .enabled(if: ProcessInfo.processInfo.environment["AURA_RENDER_EVIDENCE"] == "1"))
struct Phase2EvidenceRenderer {

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

    func render(_ model: PanelModel, over background: NSColor, appearance: NSAppearance.Name) throws -> CGImage {
        let hosting = NSHostingView(rootView: PanelView(model: model, onAction: { _ in }))
        hosting.appearance = NSAppearance(named: appearance)
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(hosting.fittingSize.height, 44))
        let bitmap = try OffscreenRender.render(hosting, over: background)
        guard let image = bitmap.context.makeImage() else { throw OffscreenRender.SampleError.noData }
        return image
    }

    /// A1（S0-1）：主 CTA「接上」改成填色底之後的 `.fullPanel`／`.banner` 兩種樣式。
    @Test("A1：主 CTA「接上」填色底（fullPanel／banner，深淺各一）")
    func renderA1Evidence() throws {
        let dir = try Self.outputDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fullPanelModel = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                             install: .notConnected, version: "1.0", optionsExpanded: false,
                                             launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true)
        let icon = IconState(activity: .working, counts: [.working: 1], liveCount: 1)
        let bannerModel = PanelModel.make(icon: icon, sessions: [session("a", .working)], palette: .default,
                                          install: .notConnected, version: "1.0", optionsExpanded: false,
                                          launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true)

        try Self.renderPair(dir: dir, name: "A1-notConnected-cta", model: fullPanelModel, render: render)
        try Self.renderPair(dir: dir, name: "A1-banner-cta", model: bannerModel, render: render)
        try Self.rebuildIndex(dir: dir)
    }

    /// A2（S0-2）：面板頂端標題與內文不再互相矛盾——`notConnected` 頂端標題現在是
    /// 「還沒接上」（原本是「沒有活著的 session」，跟 `NotConnectedView` 的內文互相矛盾）；
    /// `broken(.hookBlockedOrBroken)` 頂端標題與 footer chip 同一句。
    @Test("A2：面板標題與 tooltip 不再互相矛盾（notConnected／broken 各一）")
    func renderA2Evidence() throws {
        let dir = try Self.outputDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let notConnectedModel = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                                 install: .notConnected, version: "1.0", optionsExpanded: false,
                                                 launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true)
        let brokenModel = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                          install: .broken(.hookBlockedOrBroken, owner: .thisApp), version: "1.0",
                                          optionsExpanded: false, launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true)

        try Self.renderPair(dir: dir, name: "A2-notConnected-title", model: notConnectedModel, render: render)
        try Self.renderPair(dir: dir, name: "A2-broken-title", model: brokenModel, render: render)
        try Self.rebuildIndex(dir: dir)
    }

    /// A3：`.explainOnly` 三格現在有可行動說明文字（claudeNotFound／occupiedByFile 各一）。
    /// A4：Options 展開後第一列是「說明與快速上手…」，開關排第二（不再是第一列）。
    /// A5：`.banner` 版 CTA 現在有副標「現有掛載指向：X」。
    /// A7：banner 的生命週期——`.connected` banner 在有 session 時自動消失（對照組：無
    /// session 時仍在）；A8：圖例列已無「重設」，只在 Options 展開時看得到「重設顏色」。
    @Test("A3/A4/A5/A7/A8：說明文字／accordion 順序／banner 副標／banner 生命週期／圖例無重設")
    func renderRemainingA3ThroughA8Evidence() throws {
        let dir = try Self.outputDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // A3
        let claudeNotFound = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                             install: .claudeNotFound, version: "1.0", optionsExpanded: false,
                                             launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true)
        let occupiedByFile = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                             install: .broken(.occupiedByFile, owner: .unknown), version: "1.0",
                                             optionsExpanded: false, launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true)
        try Self.renderPair(dir: dir, name: "A3-claudeNotFound", model: claudeNotFound, render: render)
        try Self.renderPair(dir: dir, name: "A3-occupiedByFile", model: occupiedByFile, render: render)

        // A4：連上、展開 Options，第一列應是「說明與快速上手…」不是開關。
        let optionsExpanded = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                              install: .connected(owner: .thisApp, verified: .verified), version: "1.0",
                                              optionsExpanded: true, launchAtLogin: false, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true)
        try Self.renderPair(dir: dir, name: "A4-options-expanded-order", model: optionsExpanded, render: render)

        // A5：broken external ＋ 有列 → .banner 樣式，副標顯示現有掛載指向。
        let icon = IconState(activity: .working, counts: [.working: 1], liveCount: 1)
        let bannerWithSubtitle = PanelModel.make(icon: icon, sessions: [session("a", .working)], palette: .default,
                                                 install: .broken(.hookMissing, owner: .external), version: "1.0",
                                                 optionsExpanded: false, launchAtLogin: nil,
                                                 externalTargetPath: "/Users/dev/repo/plugin", banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true)
        try Self.renderPair(dir: dir, name: "A5-banner-subtitle", model: bannerWithSubtitle, render: render)

        // A7：同一個 connected() banner——沒有 session 時還在，有 session 時自動消失。
        let bannerStillThere = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                               install: .connected(owner: .thisApp, verified: .verified), version: "1.0",
                                               optionsExpanded: false, launchAtLogin: nil, externalTargetPath: nil,
                                               banner: .connected(), systemReduceMotion: false, userReduceMotion: false, iconPlate: true)
        let bannerAutoCleared = PanelModel.make(icon: icon, sessions: [session("a", .working)], palette: .default,
                                                install: .connected(owner: .thisApp, verified: .verified), version: "1.0",
                                                optionsExpanded: false, launchAtLogin: nil, externalTargetPath: nil,
                                                banner: .connected(), systemReduceMotion: false, userReduceMotion: false, iconPlate: true)
        try Self.renderPair(dir: dir, name: "A7-banner-still-there", model: bannerStillThere, render: render)
        try Self.renderPair(dir: dir, name: "A7-banner-auto-cleared", model: bannerAutoCleared, render: render)

        // A8：圖例列已無「重設」；展開 Options 才看得到「重設顏色」。
        let plainConnected = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                             install: .connected(owner: .thisApp, verified: .verified), version: "1.0",
                                             optionsExpanded: false, launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true)
        try Self.renderPair(dir: dir, name: "A8-legend-no-reset", model: plainConnected, render: render)
        try Self.renderPair(dir: dir, name: "A8-options-has-reset", model: optionsExpanded, render: render)

        try Self.rebuildIndex(dir: dir)
    }

    /// A9：team-lead 自查——「開機自動啟動」開關狀態改成自己畫的「開／關」字樣＋顏色，
    /// on／off 兩張圖現在真的不一樣（修之前是 0 px 差異）。
    /// A10：team-lead 自查——Options 8 列全展開＋一行掛載目標，列高砍半（405pt → 357pt）。
    @Test("A9/A10：開關狀態看得出來（開／關對照組）；Options 列高砍半後的 worst-case")
    func renderA9A10Evidence() throws {
        let dir = try Self.outputDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let toggleOn = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                       install: .connected(owner: .thisApp, verified: .verified), version: "1.0",
                                       optionsExpanded: true, launchAtLogin: true, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true)
        let toggleOff = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                        install: .connected(owner: .thisApp, verified: .verified), version: "1.0",
                                        optionsExpanded: true, launchAtLogin: false, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true)
        try Self.renderPair(dir: dir, name: "A9-toggle-on", model: toggleOn, render: render)
        try Self.renderPair(dir: dir, name: "A9-toggle-off", model: toggleOff, render: render)

        let worstCase = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                        install: .connected(owner: .external, verified: .unknown), version: "1.0",
                                        optionsExpanded: true, launchAtLogin: true,
                                        externalTargetPath: "/Users/dev/some/very/long/path/to/repo/plugin", banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true)
        try Self.renderPair(dir: dir, name: "A10-worst-case-height", model: worstCase, render: render)

        // A11：team-lead 自查——connected ＋ rows 空時，標題與本體先前是同一句「沒有活著的
        // session」，一字不差。本體改成有用的下一步指引，兩句不再撞字。
        let connectedEmpty = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                             install: .connected(owner: .thisApp, verified: .verified), version: "1.0",
                                             optionsExpanded: false, launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true)
        try Self.renderPair(dir: dir, name: "A11-connected-empty-no-duplicate", model: connectedEmpty, render: render)

        try Self.rebuildIndex(dir: dir)
    }

    /// 深淺各一張，共用寫檔邏輯——後續 A2…A8 沿用同一個 helper。
    static func renderPair(dir: URL, name: String, model: PanelModel,
                           render: (PanelModel, NSColor, NSAppearance.Name) throws -> CGImage) throws {
        let light = try render(model, .white, .aqua)
        try EvidenceRenderer.writePNG(light, to: dir.appendingPathComponent("\(name)-light.png"))
        let dark = try render(model, NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1), .darkAqua)
        try EvidenceRenderer.writePNG(dark, to: dir.appendingPathComponent("\(name)-dark.png"))
    }

    /// 重掃目錄現有 PNG 重建 index.html——冪等，逐 commit 累加也不會漏列。
    static func rebuildIndex(dir: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }.map(\.lastPathComponent).sorted()
        var html = """
            <!doctype html><meta charset=utf-8><title>Phase 2 A 波修復證據</title>
            <style>body{font:13px -apple-system,system-ui;padding:20px;background:#f5f5f7;color:#1d1d1f}
            img{display:block;margin:4px 0 14px;border:1px solid #d2d2d7;max-width:380px}
            .cap{color:#6e6e73;font-size:11px}</style>
            <h1>Phase 2 A 波修復證據（NSHostingView 離屏，.aqua／.darkAqua 明確指定）</h1>
            <p class=cap>背景為純色，非真實 popover 材質——版面與色點顏色可信，材質不可信。</p>\n
            """
        for file in files {
            html += "<div class=cap>\(file)</div><img src=\"\(file)\">\n"
        }
        try html.write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }
}
