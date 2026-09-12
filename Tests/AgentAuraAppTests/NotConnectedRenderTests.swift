import Testing
import AppKit
import SwiftUI
@testable import AgentAuraApp
import AuraCore

/// G8(b)(c)（spec §6.3）：`connectCTAStyle == .fullPanel` 時 `NotConnectedView` 真的取代掉
/// 一般內容（差異渲染），且 connected ＋ 有 session 時列真的畫得出來（正向對照，否則
/// 「不畫」恆真）。**固定畫布 380×320 pt**（兩狀態自然高度不同，直接逐像素相減無定義；
/// 門檻對畫布高度不敏感，不為了「看起來合理」去動畫布尺寸）。
@MainActor
@Suite("NotConnectedView 差異渲染與正向對照（G8b／G8c）")
struct NotConnectedRenderTests {
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

    func model(install: InstallState, sessions: [SessionState] = []) -> PanelModel {
        let icon = sessions.isEmpty ? IconState.empty : IconState(activity: .working, counts: [.working: 1], liveCount: 1)
        return PanelModel.make(icon: icon, sessions: sessions, palette: .default,
                               install: install, version: "1.0", optionsExpanded: false,
                               launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true)
    }

    func renderFixedCanvas(_ m: PanelModel) throws -> OffscreenRender.Bitmap {
        let hosting = NSHostingView(rootView: PanelView(model: m, onAction: { _ in }))
        return try RenderPinned.render(hosting, appearance: .aqua, canvas: Self.canvas)
    }

    @Test("(b) notConnected（.fullPanel CTA）vs connected（空 rows）差異 > 20,000 px；同內容連渲差異 == 0")
    func notConnectedDiffersFromConnected() throws {
        let notConnectedBitmap = try renderFixedCanvas(model(install: .notConnected))
        let connectedBitmap = try renderFixedCanvas(model(install: .connected(owner: .thisApp, verified: .verified)))
        let diff = try DifferingPixels.count(notConnectedBitmap, connectedBitmap)
        #expect(diff > 20_000, """
            notConnected 與 connected 的渲染差異只有 \(diff) px —— NotConnectedView 可能沒有真的取代掉一般內容
            """)

        let notConnectedAgain = try renderFixedCanvas(model(install: .notConnected))
        let sameDiff = try DifferingPixels.count(notConnectedBitmap, notConnectedAgain)
        #expect(sameDiff == 0, "同內容連渲兩次應完全一致，實際差異 \(sameDiff) px")
    }

    @Test("(c) 正向對照：connected ＋ 有 session → 列真的畫得出來（與空 rows 的 connected 差異 > 0）")
    func connectedWithSessionActuallyRendersRows() throws {
        let emptyBitmap = try renderFixedCanvas(model(install: .connected(owner: .thisApp, verified: .verified)))
        let withRowBitmap = try renderFixedCanvas(model(install: .connected(owner: .thisApp, verified: .verified),
                                                         sessions: [session("a", .working)]))
        let diff = try DifferingPixels.count(emptyBitmap, withRowBitmap)
        #expect(diff > 0, """
            connected 狀態下有無 session 的渲染結果完全相同 —— 列可能沒有真的畫出來
            （正向對照失敗：沒有這條，「不畫」在任何 mutation 下都恆真）
            """)
    }

    /// 結構性判別（補強 mutation 4 的辨別力）：純像素差異比對對「兩邊都換內容、差異量級
    /// 不變」的 routing mutation（例如把 `if model.connectCTAStyle == .fullPanel` 改成
    /// `if true`）辨別力不夠——`NotConnectedView` 的 CTA 按鈕本身仍會正確吃
    /// `model.connectCTAText == nil` 而不畫，兩邊像素總量差異看起來仍然夠大。
    /// 改用「按鈕數量差」：`NotConnectedView` 在 connected（`connectCTAText == nil`）狀態下
    /// 固定多畫一顆「這是什麼？」按鈕（CTA 按鈕本身因 `connectCTAText == nil` 不畫），
    /// 所以 notConnected（有 CTA + 「這是什麼？」兩顆）應恰好比 connected（不顯示
    /// `NotConnectedView`）多兩顆按鈕。`.title`／`.accessibilityIdentifier` 在離屏渲染下
    /// 對 SwiftUI 橋接的 NSButton 都讀不到（實測皆為空——同 S0-Q1 的 a11y 樹是 0 節點），
    /// 只有「橋接出幾顆真的 NSButton」這個數字是離屏環境測得到的。
    @Test("notConnected（顯示 NotConnectedView）應恰好比 connected（不顯示）多兩顆按鈕")
    func notConnectedViewAddsExactlyItsOwnButtons() throws {
        let connectedModel = model(install: .connected(owner: .thisApp, verified: .verified))
        let connectedHosting = NSHostingView(rootView: PanelView(model: connectedModel, onAction: { _ in }))
        connectedHosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(connectedHosting.fittingSize.height, 44))
        _ = try OffscreenRender.render(connectedHosting, over: .white)
        let connectedButtonCount = Self.allButtons(in: connectedHosting).count

        let notConnectedModel = model(install: .notConnected)
        let notConnectedHosting = NSHostingView(rootView: PanelView(model: notConnectedModel, onAction: { _ in }))
        notConnectedHosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(notConnectedHosting.fittingSize.height, 44))
        _ = try OffscreenRender.render(notConnectedHosting, over: .white)
        let notConnectedButtonCount = Self.allButtons(in: notConnectedHosting).count

        #expect(notConnectedButtonCount == connectedButtonCount + 2, """
            notConnected（顯示 NotConnectedView：CTA ＋「這是什麼？」兩顆按鈕）應該比 connected
            （不顯示 NotConnectedView）多兩顆按鈕，實際 connected=\(connectedButtonCount) notConnected=\(notConnectedButtonCount)
            """)
    }

    private static func allButtons(in view: NSView) -> [NSButton] {
        var found: [NSButton] = []
        if let button = view as? NSButton { found.append(button) }
        for sub in view.subviews { found.append(contentsOf: allButtons(in: sub)) }
        return found
    }
}
