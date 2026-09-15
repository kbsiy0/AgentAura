import Testing
import AppKit
import SwiftUI
@testable import AgentAuraApp
import AuraCore

/// T22（panel-interaction-fixes，review 退回）：`SessionsCardSizing` 第一版把
/// `rowHeight = 33` 寫死——量測時用的是「沒有 `footer` 副行」的列，沒有任何 gate 從
/// 真實 `PanelRowView` 推導它，跟 CLAUDE.md 記錄的 T16（`LEDStripView.preferredWidth`）
/// 同一族：改壞 `PanelRowView` 的 padding／字級／行數不會有任何測試變紅。
///
/// 這裡補兩條 gate：(1) 離屏渲染真實 `PanelRowView`（分別餵「沒有 footer」與「有 footer」
/// 的 session fixture），量 `NSHostingView.fittingSize.height`，斷言等於
/// `SessionsCardSizing.compactRowHeight`／`tallRowHeight`（±0.5pt）——改
/// `PanelRowView` 這條會紅。(2) 用真實量到的「有 footer」高度斷言
/// `SessionsCardSizing.cardHeight(for:)` 對單一這種列**不小於**它——這是使用者現在
/// 機器上最常見的情境（一個 session、`toolDurationMs` 非 nil 因此有 `footer` 副行，
/// 如「3s · 剛剛」），若這條不成立代表卡片會把唯一那一列裁掉一截。
@MainActor
@Suite("SessionsCardSizing 的常數真的等於 PanelRowView 量出來的高度")
struct SessionsCardSizingDerivationTests {

    /// `hasFooter == true` 時設 `toolDurationMs`，讓 `PanelRow.footer` 非空
    /// （見 `PanelViewModel.detail(for:)`）——這是「有副行」的常見成因，不是邊界情境。
    func row(hasFooter: Bool) -> PanelRow {
        let s = SessionState(id: "a", projectName: "a",
                             permissionMode: nil, effort: nil, model: nil,
                             activity: .working, mainActivity: .working, subActivity: nil,
                             currentTool: "Bash", subagentTool: nil,
                             toolDurationMs: hasFooter ? 3000 : nil,
                             turnStartedAt: nil, subagents: [:], toolFailures: 0,
                             lastMessage: nil, errorType: nil, toolError: nil,
                             liveness: .alive(pid: 1), updatedAt: Date())
        return PanelViewModel.rows(from: [s], language: .traditionalChinese).first!
    }

    func measuredHeight(_ row: PanelRow) -> CGFloat {
        let hosting = NSHostingView(rootView: PanelRowView(row: row, palette: .default))
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(hosting.fittingSize.height, 10))
        return hosting.fittingSize.height
    }

    @Test("沒有 footer 副行：真實量到的高度等於 SessionsCardSizing.compactRowHeight（±0.5pt）")
    func compactRowHeightMatchesRealMeasurement() {
        let compactRow = row(hasFooter: false)
        #expect(compactRow.footer.isEmpty, "前提：這個 fixture 不該有 footer 副行")
        let measured = measuredHeight(compactRow)
        #expect(abs(Double(measured) - SessionsCardSizing.compactRowHeight) <= 0.5, """
            真實 PanelRowView（無 footer）量到 \(measured)pt，\
            但 SessionsCardSizing.compactRowHeight = \(SessionsCardSizing.compactRowHeight)pt —— \
            兩者該對齊，PanelRowView 改了版面卻沒有同步更新常數。
            """)
    }

    @Test("有 footer 副行：真實量到的高度等於 SessionsCardSizing.tallRowHeight（±0.5pt）")
    func tallRowHeightMatchesRealMeasurement() {
        let tallRow = row(hasFooter: true)
        #expect(!tallRow.footer.isEmpty, "前提：這個 fixture 該有 footer 副行")
        let measured = measuredHeight(tallRow)
        #expect(abs(Double(measured) - SessionsCardSizing.tallRowHeight) <= 0.5, """
            真實 PanelRowView（有 footer）量到 \(measured)pt，\
            但 SessionsCardSizing.tallRowHeight = \(SessionsCardSizing.tallRowHeight)pt —— \
            兩者該對齊，PanelRowView 改了版面卻沒有同步更新常數。
            """)
    }

    /// **review 指出的具體迴歸**：使用者現在機器上就是一個有 footer 副行的 session。
    /// 若 `cardHeight` 用「沒有 footer」的假設分配空間，這唯一一列會被裁掉一截。
    @Test("使用者現在機器上的情境（單一 session、有 footer 副行）：cardHeight 不小於真實高度，不裁切")
    func cardHeightNeverClipsASingleTallRow() {
        let tallRow = row(hasFooter: true)
        let measured = measuredHeight(tallRow)
        let cardHeight = SessionsCardSizing.cardHeight(for: [tallRow])
        #expect(cardHeight >= Double(measured), """
            單一有 footer 副行的列，cardHeight = \(cardHeight)pt，\
            但真實渲染需要 \(measured)pt —— 卡片會把這一列裁掉一截，\
            使用者得在只有一列的卡片裡捲動才看得到完整內容。
            """)
    }
}
