import Testing
import AppKit
import SwiftUI
@testable import AgentAuraApp
import AuraCore

/// T09（CX22 像素半／CX23）：`PanelRowView` 的第一行 `HStack` 依 `row.agentLabel` 多畫一個
/// 「Codex」小標籤（D-l）——這裡驗兩件事：(1) 有標籤真的畫得出來（像素差異 > 0，CX22 像素半，
/// AuraCore 的 model 半見 `CodexRowLabelTests`）；(2) 標籤放在**既有第一行**、不另起一行，
/// 量渲染後的真實高度（不是宣告順序，同 CLAUDE.md 的 gate 哲學第 4 條）——列高仍是 43／59pt，
/// 跟 `SessionsCardSizingDerivationTests` 量到的常數同一個 oracle。
@MainActor
@Suite("Codex agentLabel 的像素差異與列高（CX22 像素半／CX23）")
struct CodexRowLabelRenderTests {

    /// `agent` 是唯一變動維度——其餘欄位跟 `SessionsCardSizingDerivationTests.row(hasFooter:)`
    /// 同一份 fixture 手法，`hasFooter` 決定 `toolDurationMs` 有無（有 footer 副行才會撐出
    /// tallRowHeight）。
    func row(agent: Agent, hasFooter: Bool) -> PanelRow {
        let s = SessionState(id: "a", projectName: "a",
                             permissionMode: nil, effort: nil, model: nil, agent: agent,
                             activity: .working, mainActivity: .working, subActivity: nil,
                             currentTool: "Bash", subagentTool: nil,
                             toolDurationMs: hasFooter ? 3000 : nil,
                             turnStartedAt: nil, subagents: [:], toolFailures: 0,
                             lastMessage: nil, errorType: nil, toolError: nil,
                             liveness: .alive(pid: 1), updatedAt: Date())
        return PanelViewModel.rows(from: [s], language: .traditionalChinese).first!
    }

    /// `minimumForegroundPixels` 覆寫成 1000（`RenderPinned` 預設 2000 是為整張面板／整個
    /// footer 校準的，單獨一列的墨量天生少很多）——實測四格（claude／codex × 無/有 footer）
    /// 非背景像素分別是 1265／2501／2170／3406，最小值 1265，這裡取一個明顯低於最小實測值、
    /// 仍遠高於 0 的門檻，證明畫布真的畫出東西、不是空轉。
    func renderRow(_ row: PanelRow) throws -> OffscreenRender.Bitmap {
        let hosting = NSHostingView(rootView: PanelRowView(row: row, palette: .default))
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(hosting.fittingSize.height, 10))
        return try RenderPinned.render(hosting, appearance: .aqua, canvas: NSSize(width: 380, height: hosting.fittingSize.height),
                                       minimumForegroundPixels: 1000)
    }

    func measuredHeight(_ row: PanelRow) -> CGFloat {
        let hosting = NSHostingView(rootView: PanelRowView(row: row, palette: .default))
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(hosting.fittingSize.height, 10))
        return hosting.fittingSize.height
    }

    /// CX22 像素半：同一列（除了 `agent`）claude vs codex，渲染結果必須不同。
    @Test("同一列 .claude vs .codex 渲染差異 > 0（無 footer／有 footer 兩種列高都驗）", arguments: [false, true])
    func codexLabelProducesPixelDifference(hasFooter: Bool) throws {
        let claudeRow = row(agent: .claude, hasFooter: hasFooter)
        let codexRow = row(agent: .codex, hasFooter: hasFooter)
        #expect(claudeRow.agentLabel == nil, "前提：.claude 不該有 agentLabel")
        #expect(codexRow.agentLabel == "Codex", "前提：.codex 應該有字面 \"Codex\"")

        let claudeBitmap = try renderRow(claudeRow)
        let codexBitmap = try renderRow(codexRow)
        let diff = try DifferingPixels.count(claudeBitmap, codexBitmap)
        #expect(diff > 0, """
            hasFooter=\(hasFooter)：.claude 與 .codex 渲染結果完全相同 —— agentLabel 可能沒有真的畫出來
            """)
    }

    /// CX23：帶標籤的列高仍是 SessionsCardSizingDerivationTests 量到的常數（±0.5pt）——
    /// 若標籤被畫成另起一行，這裡的高度會比 compactRowHeight／tallRowHeight 多至少一行字高，
    /// 遠超 0.5pt 誤差。單位：pt（`NSHostingView.fittingSize` 本身就是 AppKit 點座標系統）。
    @Test("codex 標籤不改變列高：無 footer 仍是 compactRowHeight，有 footer 仍是 tallRowHeight（±0.5pt）")
    func codexLabelDoesNotChangeRowHeight() {
        let compact = measuredHeight(row(agent: .codex, hasFooter: false))
        #expect(abs(Double(compact) - SessionsCardSizing.compactRowHeight) <= 0.5, """
            帶 Codex 標籤、無 footer 的列量到 \(compact)pt，\
            但 SessionsCardSizing.compactRowHeight = \(SessionsCardSizing.compactRowHeight)pt —— \
            標籤可能被畫成另起一行，撐高了列高
            """)
        let tall = measuredHeight(row(agent: .codex, hasFooter: true))
        #expect(abs(Double(tall) - SessionsCardSizing.tallRowHeight) <= 0.5, """
            帶 Codex 標籤、有 footer 的列量到 \(tall)pt，\
            但 SessionsCardSizing.tallRowHeight = \(SessionsCardSizing.tallRowHeight)pt —— \
            標籤可能被畫成另起一行，撐高了列高
            """)
    }
}
