import AppKit

extension StatusItemController {
    /// T18：色板要避開的矩形。**面板已顯示就回面板自己的視窗 frame**——色板要放在它旁邊，
    /// 而不是下方（T17 放下方，實機被面板整個蓋住）。面板還沒開就退回選單列圖示的位置。
    ///
    /// 測試環境的 status item 沒有 window，所以回 nil——色板的位置因此退回系統預設，
    /// 不是壞掉（`ColorPickerCoordinator.plannedFrame` 對 nil 回 nil）。
    ///
    /// 拆成獨立檔案只因為 `StatusItemController.swift` 撞到 200 行上限
    /// （`IsolationTests.fileLengthLimit`），不是為了抽象。
    var avoidScreenFrame: CGRect? {
        if let panelWindow = hostingController?.view.window, panelWindow.isVisible {
            return panelWindow.frame
        }
        guard let button = item.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
}
