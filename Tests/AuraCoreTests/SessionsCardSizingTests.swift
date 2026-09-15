import Testing
import Foundation
import AuraCore

/// T22（panel-interaction-fixes）：`SessionsCardSizing` 的推導公式本身——真的用它擋
/// `ScrollView` 高度、且常數等於真實 view 量測值的部分由 `SessionsCardSizingDerivationTests`
/// （`Tests/AgentAuraAppTests/`，需要 AppKit 渲染 `PanelRowView`）守，同 `OptionsPanelSizing`
/// 既有的兩層分工。
@Suite("SessionsCardSizing：高度由真實列內容推導")
struct SessionsCardSizingTests {

    func row(footer hasFooter: Bool) -> PanelRow {
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

    @Test("空陣列：高度為 0")
    func emptyRowsIsZero() {
        #expect(SessionsCardSizing.contentHeight(for: []) == 0)
        #expect(SessionsCardSizing.cardHeight(for: []) == 0)
    }

    @Test("單一沒有 footer 副行的列：高度恰為 compactRowHeight，無分隔線")
    func singleCompactRow() {
        let rows = [row(footer: false)]
        #expect(SessionsCardSizing.contentHeight(for: rows) == SessionsCardSizing.compactRowHeight)
    }

    @Test("單一有 footer 副行的列：高度恰為 tallRowHeight（不是被 compactRowHeight 裁掉）")
    func singleTallRow() {
        let rows = [row(footer: true)]
        #expect(SessionsCardSizing.contentHeight(for: rows) == SessionsCardSizing.tallRowHeight)
        #expect(SessionsCardSizing.tallRowHeight > SessionsCardSizing.compactRowHeight, """
            有 footer 副行的列理應比沒有的高，否則這條測試本身量不出裁切迴歸
            """)
    }

    @Test("混合列：逐列依 footer.isEmpty 各自累加，不是用同一個常數乘列數")
    func mixedRowsSumPerRowHeight() {
        let rows = [row(footer: true), row(footer: false), row(footer: true)]
        let expected = SessionsCardSizing.tallRowHeight + SessionsCardSizing.compactRowHeight
            + SessionsCardSizing.tallRowHeight + 2 * SessionsCardSizing.dividerHeight
        #expect(SessionsCardSizing.contentHeight(for: rows) == expected, """
            3 列（tall／compact／tall）＋2 條分隔線的總高應該恰為逐列相加，實際 \
            \(SessionsCardSizing.contentHeight(for: rows))，預期 \(expected)
            """)
    }

    @Test("超過 420pt 的內容會被夾住，cardHeight 不超過 maxHeight")
    func cardHeightClampsToMaxHeight() {
        let manyTallRows = Array(repeating: row(footer: true), count: 20)
        let content = SessionsCardSizing.contentHeight(for: manyTallRows)
        #expect(content > SessionsCardSizing.maxHeight, "前提：20 列全部有 footer 應該遠超過 420pt")
        #expect(SessionsCardSizing.cardHeight(for: manyTallRows) == SessionsCardSizing.maxHeight)
    }
}
