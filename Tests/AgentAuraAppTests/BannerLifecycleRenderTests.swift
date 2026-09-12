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
        let hosting = NSHostingView(rootView: BannerView(banner: .connected(), onAction: { _ in }))
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
}
