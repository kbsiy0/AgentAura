import Testing
@testable import AgentAuraApp

/// T20：`.semitransient` 釘住期間我們自己接管關閉決定——這裡守純函式那一半，三個安全區
/// （popover／色板／錨點）各驗一次，加一個「三者都不是」的外部點擊。
@Suite("PanelDismissPolicy（T20）")
struct PanelDismissPolicyTests {

    @Test("三個安全區的點擊都不該關；三者都不是才算外部、該關")
    func shouldCloseOnlyForTrulyExternalClicks() {
        let popover = 10, colorPanel = 20, anchor = 30

        #expect(PanelDismissPolicy.shouldClose(clickedWindowNumber: popover, popoverWindowNumber: popover,
                                               colorPanelWindowNumber: colorPanel, anchorWindowNumber: anchor) == false,
                "點在 popover 自己身上不該關")
        #expect(PanelDismissPolicy.shouldClose(clickedWindowNumber: colorPanel, popoverWindowNumber: popover,
                                               colorPanelWindowNumber: colorPanel, anchorWindowNumber: anchor) == false,
                "**使用者回報的 bug**：點在色板身上不該關，否則沒法邊拖邊選色")
        #expect(PanelDismissPolicy.shouldClose(clickedWindowNumber: anchor, popoverWindowNumber: popover,
                                               colorPanelWindowNumber: colorPanel, anchorWindowNumber: anchor) == false,
                """
                點在選單列圖示（anchor）不該由我們關——要讓 togglePopover 自己的 toggle 邏輯決定，\
                否則會跟它的 mouseUp 打架，變成「關了又立刻被撐開」
                """)
        #expect(PanelDismissPolicy.shouldClose(clickedWindowNumber: 999, popoverWindowNumber: popover,
                                               colorPanelWindowNumber: colorPanel, anchorWindowNumber: anchor) == true,
                "**使用者回報的 bug**：三者都不是（真正的外部點擊）必須關")
    }

    @Test("色板還沒開（colorPanelWindowNumber 為 nil）時，非 popover／anchor 的點擊仍該關")
    func closesWhenColorPanelNotOpen() {
        #expect(PanelDismissPolicy.shouldClose(clickedWindowNumber: 5, popoverWindowNumber: 1,
                                               colorPanelWindowNumber: nil, anchorWindowNumber: 2) == true)
    }
}
