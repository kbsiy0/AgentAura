import Testing
import AppKit
import SwiftUI
@testable import AgentAuraApp
import AuraCore

/// T11 commit1（S0-1）：主 CTA「接上」必須真的長得像按鈕——persona 實測舊版
/// `Button(cta) { }`（標題式）在離屏渲染下只拿系統次要前景色（#7f7f7f，4.00:1，
/// 跟旁邊的說明句同色，`.banner` 版更糟：狀態文字與按鈕最深像素都是 112）。
///
/// 兩條斷言對齊團隊主管的兩個硬性要求：
/// (a) CTA 區域存在「填色底」——`count(near: CTAButtonStyle.fill)` 必須遠高於
///     舊寫法能產生的量（標題式 `.borderless` 不畫任何填色矩形，只有反鋸齒文字像素，
///     revert 回舊寫法會讓這個數字掉到接近 0——這是本檔的 mutation 目標）。
/// (b) CTA 文字對比 ≥ 4.5:1——直接對 `CTAButtonStyle` 的兩個常數算 WCAG 對比。
///     色值寫死、不吃系統 accent／appearance，所以「深淺兩種 appearance 各自量」
///     必然算出同一個數字；`ctaRendersIdenticallyAcrossAppearances` 額外用**渲染**
///     證明這件事不是巧合——真的用 `.aqua`／`.darkAqua` 兩種 appearance 渲一次，
///     兩張圖裡 CTA 填色像素數必須相等（同一組色值，不隨 appearance 變化）。
@MainActor
@Suite("CTA「接上」看起來像按鈕（S0-1，T11 commit1）")
struct CTAAffordanceRenderTests {
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

    func fullPanelModel() -> PanelModel {
        PanelModel.make(icon: .empty, sessions: [], palette: .default,
                        install: .notConnected, version: "1.0", optionsExpanded: false,
                        launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese)
    }

    func bannerModel() -> PanelModel {
        let icon = IconState(activity: .working, counts: [.working: 1], liveCount: 1)
        return PanelModel.make(icon: icon, sessions: [session("a", .working)], palette: .default,
                               install: .notConnected, version: "1.0", optionsExpanded: false,
                               launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese)
    }

    func render(_ m: PanelModel, appearance: NSAppearance.Name = .aqua) throws -> OffscreenRender.Bitmap {
        let hosting = NSHostingView(rootView: PanelView(model: m, onAction: { _ in }))
        return try RenderPinned.render(hosting, appearance: appearance, canvas: Self.canvas)
    }

    @Test("(a) .fullPanel CTA 有真的填色底（≥ 400 px）")
    func fullPanelCTAHasFilledBackground() throws {
        #expect(fullPanelModel().connectCTAStyle == .fullPanel, "前提：notConnected ＋ 空 rows 應該是 .fullPanel")
        let bitmap = try render(fullPanelModel())
        let fillPixels = bitmap.count(near: CTAButtonStyle.fill)
        // 實測 ~660 px（87×15pt 可點框 @2x ≈ 5,220 px² 的填色部分，扣掉文字反鋸齒與圓角）；
        // 門檻抓遠低於實測值但遠高於「舊寫法幾乎 0」，兩邊都留足邊際。
        #expect(fillPixels >= 400, """
            .fullPanel CTA 的填色底像素只有 \(fillPixels) —— 標題式 `Button(cta)` 不會畫出任何填色矩形
            （只有反鋸齒文字），這個數字太低代表 CTA 可能又退回「看不出是按鈕」的舊寫法
            """)
    }

    @Test("(a) .banner CTA 有真的填色底（≥ 200 px，窄條版內距較小）")
    func bannerCTAHasFilledBackground() throws {
        #expect(bannerModel().connectCTAStyle == .banner, "前提：notConnected ＋ 非空 rows 應該是 .banner")
        let bitmap = try render(bannerModel())
        let fillPixels = bitmap.count(near: CTAButtonStyle.fill)
        #expect(fillPixels >= 200, """
            .banner CTA 的填色底像素只有 \(fillPixels) —— persona 實測舊版窄條左邊的狀態文字
            與右邊的按鈕最深像素都是 112（看不出哪一半可以按），這個數字太低代表同一個問題還在
            """)
    }

    @Test("(b) CTAButtonStyle.fill／.text 的 WCAG 對比 ≥ 4.5:1（色值寫死，兩種 appearance 同一個數字）")
    func ctaFillTextContrastMeetsWCAG_AA() {
        let contrast = OffscreenRender.contrast(CTAButtonStyle.fill, CTAButtonStyle.text)
        #expect(contrast >= 4.5, "CTA 填色底／文字對比只有 \(contrast) —— 低於 WCAG AA 一般文字門檻 4.5:1")
    }

    @Test("(b) CTA 填色底不得與說明文字的中性灰同色（maxComponentDelta 遠高於容差）")
    func ctaFillDiffersFromCaptionGray() {
        // persona 實測舊版說明句量到 #808080（128/255 中性灰）——這裡直接對常數比較，
        // 不用猜面板版面裡說明句的確切 y 座標（版面隨 banner／options 展開會位移，猜座標很脆）。
        let captionGray = RGBA(r: 128.0 / 255, g: 128.0 / 255, b: 128.0 / 255, a: 1)
        let delta = CTAButtonStyle.fill.maxComponentDelta(captionGray)
        #expect(delta > 0.3, "CTA 填色底（\(CTAButtonStyle.fill)）與說明文字灰（\(captionGray)）差只有 \(delta) —— 太接近，看起來會像同一種元素")
    }

    @Test("渲染層對照：CTA 填色像素數在 .aqua／.darkAqua 兩種 appearance 下相等（色值寫死，不隨 appearance 變化）")
    func ctaRendersIdenticallyAcrossAppearances() throws {
        let light = try render(fullPanelModel(), appearance: .aqua)
        let dark = try render(fullPanelModel(), appearance: .darkAqua)
        let lightPixels = light.count(near: CTAButtonStyle.fill)
        let darkPixels = dark.count(near: CTAButtonStyle.fill)
        #expect(lightPixels == darkPixels, """
            .aqua 填色像素 \(lightPixels) 與 .darkAqua 填色像素 \(darkPixels) 不相等 ——
            CTA 色值理論上寫死不隨 appearance 變化，兩者應完全相同
            """)
        #expect(lightPixels >= 400, "前提：.aqua 下也要真的畫出填色底（同 fullPanelCTAHasFilledBackground）")
    }
}
