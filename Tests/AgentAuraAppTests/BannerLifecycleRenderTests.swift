import Testing
import AppKit
import SwiftUI
@testable import AgentAuraApp
import AuraCore

/// A7(b)（T11 commit3）：persona 量到 banner 的 ✕ 只有 10×10pt，低於 macOS 舒適門檻。
/// 修法沿用既有「10pt 視覺／20pt 命中」做法（`LegendRowView.LegendDot`）——視覺字重不變，
/// 只放大可點區。走真的 `BannerView`，離屏渲染強迫 AppKit 橋接成真的 `NSButton`，
/// 直接讀它的 `frame`（同 `NotConnectedRenderTests`／`PanelPixelTests` 既有的量測手法）。
@MainActor
@Suite("Banner ✕ 的可點區（A7(b)，T11 commit3）")
struct BannerLifecycleRenderTests {

    @Test("banner ✕ 的可點區 ≥ 20×20pt")
    func dismissButtonHitAreaIsAtLeast20pt() throws {
        let hosting = NSHostingView(rootView: BannerView(banner: .connected(language: .traditionalChinese), onAction: { _ in }))
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(hosting.fittingSize.height, 30))
        _ = try OffscreenRender.render(hosting, over: .white)   // 強迫 layout，AppKit 橋接的按鈕才真的存在

        let buttons = Self.allButtons(in: hosting)
        let button = try #require(buttons.first, "BannerView 應該有一顆可關閉按鈕")
        #expect(button.frame.width >= 20 && button.frame.height >= 20, """
            ✕ 按鈕可點區只有 \(button.frame.width)×\(button.frame.height)pt —— 低於 20pt 舒適門檻
            （既有做法：`LegendRowView.LegendDot` 10pt 視覺／20pt 命中）
            """)
    }

    private static func allButtons(in view: NSView) -> [NSButton] {
        var found: [NSButton] = []
        if let button = view as? NSButton { found.append(button) }
        for sub in view.subviews { found.append(contentsOf: allButtons(in: sub)) }
        return found
    }

    /// r1 review m5：`L10nCodexCardTextTests.panelBannerCodexConnectedUsesTheSameOracle`
    /// 改寫後只剩註解宣稱「`.codexConnected` 不會被歸進 `.error` 的紅色分支」，沒有任何斷言
    /// 釘住它——這裡補上真的像素斷言。`.error` 背景是 `Color.red.opacity(0.12)`（over white
    /// 約 RGBA(1, 0.88, 0.88)），`.connected`／`.codexConnected` 都走 `Color.accentColor.opacity(0.12)`
    /// （非紅）。
    ///
    /// r2 review N3 兩處更正：
    /// ① **改走 `RenderPinned`**（不得繞過——它是所有新離屏渲染共用的前提：釘 `.aqua`
    /// appearance、內建非背景像素空轉檢查）。
    /// ② **`>= 40_000` 原本是沒有推導過的絕對數字**——不同文案的紅底填色比例不同
    /// （短文字 `.error("x")` 幾乎整張畫布是紅，長文字的卡片文字覆蓋掉更多紅色像素），
    /// 換一段更長的 `.error` 文案就可能假紅。改成從**當次渲染的畫布面積**推導門檻
    /// （`totalPixels / 2`）——只要红色調覆蓋過半畫布就算「真的畫出紅底」，不綁死某一種文案
    /// 量出來的絕對值。
    @Test("`.error` banner 背景是紅色調；`.connected`／`.codexConnected` 都不是（同一套成功色）")
    func codexConnectedBannerIsNotRoutedToTheErrorColorBranch() throws {
        let redish = RGBA(r: 1.0, g: 0.88, b: 0.88, a: 1)
        func redHitCount(_ banner: PanelBanner) throws -> (hits: Int, total: Int) {
            let hosting = NSHostingView(rootView: BannerView(banner: banner, onAction: { _ in }))
            let height = max(hosting.fittingSize.height, 30)
            // r2 review N3①：一律經 RenderPinned（不繞過它的 appearance 釘死與空轉前提）。
            let bitmap = try RenderPinned.render(hosting, appearance: .aqua,
                                                 canvas: NSSize(width: 380, height: height),
                                                 minimumForegroundPixels: 1)
            return (bitmap.count(near: redish, tolerance: 0.03), bitmap.context.width * bitmap.context.height)
        }
        let error = try redHitCount(.error("x"))
        let errorThreshold = error.total / 2   // r2 review N3②：從畫布面積推導，不是寫死的絕對數字。
        #expect(error.hits >= errorThreshold, """
            .error banner 應該真的畫出紅色調背景（覆蓋畫布過半），實際命中 \(error.hits) / \(error.total) px
            （門檻 \(errorThreshold)＝畫布面積的一半）
            """)

        let connected = try redHitCount(.connected(language: .english))
        #expect(connected.hits == 0, ".connected banner 不該有紅色調背景，實際命中 \(connected.hits) px")

        let codexConnected = try redHitCount(.codexConnected(language: .english))
        #expect(codexConnected.hits == 0, """
            .codexConnected banner（T13b 新 kind）不該被誤歸進 .error 的紅色分支，
            實際命中 \(codexConnected.hits) px
            """)
    }

    /// r2 review N3③（G11 同型的分離格）：上面那條測試靠「count(near: 一個寫死的紅色調 fixture）」
    /// 分辨 `.error`（真紅）與 `.connected`／`.codexConnected`（`Color.accentColor`）——這個方法
    /// 本身依賴「fixture 顏色」與「使用者系統目前的 accent color」離得夠遠。**這裡把這個前提
    /// 變成一條會失敗的斷言，不是背景假設**：若使用者把系統 accent color 設成接近紅色的色調，
    /// `Color.accentColor.opacity(0.12)` 渲出來的顏色可能跟 `.error` 的紅色調 fixture 靠得太近，
    /// 上面那條測試的方法論在那種機器上就不可靠——這條 gate 會先紅，明確指出「這個方法此刻
    /// 在這台機器上不成立」，而不是讓上面那條測試安靜地量出誤判的結果。門檻同既有 G11
    /// （`healthTonesDontCollideWithWildPalette`）：`maxComponentDelta > 0.063`。
    @Test("fixture 的紅色調 與目前系統 accent color 的 maxComponentDelta > 0.063（G11 同型）")
    func redFixtureIsSeparatedFromCurrentAccentColor() {
        let redish = RGBA(r: 1.0, g: 0.88, b: 0.88, a: 1)
        let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor.controlAccentColor
        let accentRGBA = RGBA(r: accent.redComponent, g: accent.greenComponent, b: accent.blueComponent, a: 1)
        let delta = redish.maxComponentDelta(accentRGBA)
        #expect(delta > 0.063, """
            紅色調 fixture（\(redish)）與目前系統 accent color（\(accentRGBA)）的 maxComponentDelta
            只有 \(delta)——低於 0.063 代表上面那條測試的「數紅色像素」方法論在這台機器目前的
            accent color 設定下不可靠（`.codexConnected` 真的用 accentColor 畫，也可能被誤數成紅）。
            """)
    }
}
