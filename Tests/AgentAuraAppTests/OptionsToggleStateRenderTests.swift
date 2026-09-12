import Testing
import AppKit
import SwiftUI
@testable import AgentAuraApp
import AuraCore

/// A9（T11 commit3，team-lead 自查）：team-lead 實測離屏渲染下 `Toggle` 的 on／off 兩張圖
/// **完全一樣**（診斷量到 0 px 差異）——同 CLAUDE.md「這個 codebase 的 gate 哲學」第 4 條：
/// 渲不出來的狀態指示，我們就沒有辦法驗證使用者看不看得到。修法：`Toggle` 保留（真的觸發
/// 互動），但狀態另外自己畫一個「開／關」字樣＋顏色，兩者都是渲染保證畫得出來的。
@MainActor
@Suite("開機自動啟動的開關狀態渲染得出來（A9，T11 commit3）")
struct OptionsToggleStateRenderTests {

    func model(launchAtLogin: Bool) -> PanelModel {
        PanelModel.make(icon: .empty, sessions: [], palette: .default,
                        install: .connected(owner: .thisApp, verified: .verified), version: "1.0",
                        optionsExpanded: true, launchAtLogin: launchAtLogin, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true)
    }

    func render(_ m: PanelModel) throws -> OffscreenRender.Bitmap {
        let hosting = NSHostingView(rootView: PanelView(model: m, onAction: { _ in }))
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(hosting.fittingSize.height, 44))
        return try OffscreenRender.render(hosting, over: .white)
    }

    @Test("launchAtLogin true 與 false 的渲染必須不同（≥ 100 px 差異）")
    func toggleStateIsVisuallyDistinguishable() throws {
        let onBitmap = try render(model(launchAtLogin: true))
        let offBitmap = try render(model(launchAtLogin: false))
        let diff = try DifferingPixels.count(onBitmap, offBitmap)
        // 實測 461 px（修之前是 0）——門檻抓遠低於實測值但遠高於 0，兩邊都留邊際。
        #expect(diff >= 100, """
            開／關兩張圖的渲染差異只有 \(diff) px —— 修之前這個數字是 0（SwiftUI `Toggle`
            在離屏渲染下 on／off 完全一樣），使用者在真實 popover 材質下可能也分不出目前是開是關。
            """)
    }
}
