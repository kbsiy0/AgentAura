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
    /// （非紅）。實測：`.error` 命中該紅色調 ≥ 40,000 px，`.connected`／`.codexConnected` 皆 0。
    @Test("`.error` banner 背景是紅色調；`.connected`／`.codexConnected` 都不是（同一套成功色）")
    func codexConnectedBannerIsNotRoutedToTheErrorColorBranch() throws {
        let redish = RGBA(r: 1.0, g: 0.88, b: 0.88, a: 1)
        func redHitCount(_ banner: PanelBanner) throws -> Int {
            let hosting = NSHostingView(rootView: BannerView(banner: banner, onAction: { _ in }))
            hosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(hosting.fittingSize.height, 30))
            let bitmap = try OffscreenRender.render(hosting, over: .white)
            return bitmap.count(near: redish, tolerance: 0.03)
        }
        let errorHits = try redHitCount(.error("x"))
        #expect(errorHits >= 40_000, ".error banner 應該真的畫出紅色調背景，實際命中 \(errorHits) px")

        let connectedHits = try redHitCount(.connected(language: .english))
        #expect(connectedHits == 0, ".connected banner 不該有紅色調背景，實際命中 \(connectedHits) px")

        let codexConnectedHits = try redHitCount(.codexConnected(language: .english))
        #expect(codexConnectedHits == 0, """
            .codexConnected banner（T13b 新 kind）不該被誤歸進 .error 的紅色分支，
            實際命中 \(codexConnectedHits) px
            """)
    }
}
