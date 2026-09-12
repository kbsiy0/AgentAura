import Foundation

/// D-i：色板改色期間面板釘住為 `.semitransient`，但那個 behavior 只在「切到別的 app」時
/// 才自動關閉——點擊「同一個 app 內、色板以外」的地方完全不會關（實機回報的 T20 bug②，
/// 使用者只能回去點選單列圖示才能收起面板）。我們自己接管這個決定，這裡是純函式那一半：
/// 只吃三個 window number，不碰任何 `NSEvent`／`NSWindow`（見 `PanelDismissMonitor`）。
enum PanelDismissPolicy {
    /// 三個安全區——popover 自己、色板本身（D-i 期間點色板不能算「外部」，否則沒法邊拖邊
    /// 選色）、選單列圖示的 anchor（`StatusItemController.togglePopover` 的既有 toggle 邏輯
    /// 已經專門處理它；我們搶著關會跟它的 mouseUp 打架，變成「關了又立刻被撐開」）。
    /// 三者都不是才算外部點擊，該關。
    static func shouldClose(clickedWindowNumber: Int, popoverWindowNumber: Int?,
                            colorPanelWindowNumber: Int?, anchorWindowNumber: Int?) -> Bool {
        clickedWindowNumber != popoverWindowNumber
            && clickedWindowNumber != colorPanelWindowNumber
            && clickedWindowNumber != anchorWindowNumber
    }
}
