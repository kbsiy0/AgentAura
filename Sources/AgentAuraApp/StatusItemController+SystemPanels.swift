import AppKit

extension StatusItemController {
    /// 真的選單列圖示 ⇒ 真的系統面板。`AppDelegate` 用這個值設定
    /// `ColorPickerCoordinator.presentsPanel`：色板是掛在選單列圖示旁邊的，只有擁有
    /// 真圖示的 renderer 才有資格把 `NSColorPanel.shared` 叫到螢幕上。測試的 `SpyRenderer`
    /// 回 `false`——它沒有圖示、沒有視窗，`orderFront` 出來的色板只會落在開發者的桌面上
    /// （2026-09-19 實機回報：多個 worktree 並行跑測試時色板不斷跳出）。
    ///
    /// 放在獨立檔案是因為 `StatusItemController.swift` 已貼著 200 行上限。
    var presentsSystemPanels: Bool { true }
}
