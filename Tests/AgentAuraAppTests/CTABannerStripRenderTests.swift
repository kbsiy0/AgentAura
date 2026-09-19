import Testing
import AppKit
import SwiftUI
@testable import AgentAuraApp
import AuraCore

/// `ctaBannerStyleRendersStrip`（spec §3.3／C1，T08）：有活著的列時 `connectCTAStyle == .banner`
/// 要真的多畫一條窄條（`ConnectCTABannerView`），不是「有 chip 但沒有任何可按的東西」
/// （S1-P4：移除掛載之後仍有活著的列那個情境）。固定畫布（同 `NotConnectedRenderTests`
/// 380×320 pt）＋ `RenderPinned` 前提斷言，正向對照 `.fullPanel` 與 `.banner` 兩種樣式
/// 的渲染必須不同（不是同一段程式碼恰好長得一樣）。
@MainActor
@Suite("CTA banner 窄條真的多畫東西（ctaBannerStyleRendersStrip）", .serialized)
struct CTABannerStripRenderTests {
    static let canvas = NSSize(width: 380, height: 320)

    func session(_ id: String, _ a: Activity) -> SessionState {
        SessionState(id: id, projectName: id,
                    permissionMode: nil, effort: nil, model: nil,
                    activity: a, mainActivity: a, subActivity: nil,
                    currentTool: "Bash", subagentTool: nil, toolDurationMs: nil,
                    turnStartedAt: nil, subagents: [:], toolFailures: 0,
                    lastMessage: nil, errorType: nil, toolError: nil,
                    liveness: .alive(pid: 1), updatedAt: Date())
    }

    func model(install: InstallState, sessions: [SessionState]) -> PanelModel {
        let icon = IconState(activity: .working, counts: [.working: 1], liveCount: 1)
        return PanelModel.make(icon: icon, sessions: sessions, palette: .default,
                               install: install, version: "1.0", optionsExpanded: false,
                               launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese, codex: .unavailable, codexSnippet: nil, codexPathRejection: nil)
    }

    func renderFixedCanvas(_ m: PanelModel) throws -> OffscreenRender.Bitmap {
        let hosting = NSHostingView(rootView: PanelView(model: m, onAction: { _ in }))
        return try RenderPinned.render(hosting, appearance: .aqua, canvas: Self.canvas)
    }

    @Test("同一組非空 rows：showsConnectCTA true（.banner）vs false（.none）渲染差異 > 3,000 px")
    func bannerStyleDiffersFromNoCTA() throws {
        let rows = [session("a", .working)]
        let bannerModel = model(install: .notConnected, sessions: rows)
        #expect(bannerModel.connectCTAStyle == .banner, "前提：notConnected ＋ 非空 rows 應該是 .banner 樣式")
        let noCTAModel = model(install: .connected(owner: .thisApp, verified: .verified), sessions: rows)
        #expect(noCTAModel.connectCTAStyle == .none, "前提：connected 應該是 .none 樣式")

        let bannerBitmap = try renderFixedCanvas(bannerModel)
        let noCTABitmap = try renderFixedCanvas(noCTAModel)
        let diff = try DifferingPixels.count(bannerBitmap, noCTABitmap)
        // 實測 47,368 px（門檻抓半數量級以下，同 G8b「門檻對畫布不敏感」的抓法）。
        #expect(diff > 20_000, """
            .banner 與 .none 樣式（同一組 rows）的渲染差異只有 \(diff) px ——
            ConnectCTABannerView 可能沒有真的多畫東西（S1-P4：有 chip 但沒有任何可按的東西）
            """)

        let bannerAgain = try renderFixedCanvas(bannerModel)
        let sameDiff = try DifferingPixels.count(bannerBitmap, bannerAgain)
        #expect(sameDiff == 0, "同內容連渲兩次應完全一致，實際差異 \(sameDiff) px")
    }

    @Test("正向對照：.fullPanel（rows 空）與 .banner（rows 非空）兩種 CTA 樣式渲染必須不同")
    func fullPanelStyleDiffersFromBannerStyle() throws {
        let fullPanelModel = model(install: .notConnected, sessions: [])
        #expect(fullPanelModel.connectCTAStyle == .fullPanel, "前提：notConnected ＋ 空 rows 應該是 .fullPanel 樣式")
        let bannerModel = model(install: .notConnected, sessions: [session("a", .working)])
        #expect(bannerModel.connectCTAStyle == .banner, "前提：notConnected ＋ 非空 rows 應該是 .banner 樣式")

        let fullPanelBitmap = try renderFixedCanvas(fullPanelModel)
        let bannerBitmap = try renderFixedCanvas(bannerModel)
        let diff = try DifferingPixels.count(fullPanelBitmap, bannerBitmap)
        // 實測 56,037 px。
        #expect(diff > 20_000, """
            .fullPanel 與 .banner 兩種 CTA 樣式的渲染差異只有 \(diff) px —— 看起來像同一段程式碼，
            不是「整版 CTA」與「列上方窄條」兩種真的不同的呈現
            """)
    }
}
