import AppKit
import AuraCore

/// T32：造型可換——拆檔理由同 `+IconFrame.swift`／`+Dismiss.swift`／`+Tooltip.swift`
/// （避免 `StatusItemController.swift` 撞 200 行上限），不是抽象邊界。
extension StatusItemController {
    /// icon 在 status item 按鈕裡左右各留的邊距（pt）。`item.length` 因此是
    /// `preferredWidth + horizontalPadding * 2`，view 的原點 x 也是它——兩個數字是
    /// **同一個決定的兩半**，所以只准有一份（reuse#2：原本 `+ 8` 與 `x: 4` 各自散在
    /// `init` 與 `setIconShape` 兩處，改一處另一處就偏移或被裁）。
    static let horizontalPadding: CGFloat = 4

    /// 把 `view` 掛上 status item 按鈕並調整寬度——`init` 與 `setIconShape` 共用同一份程序。
    /// `static`：`init` 在所有 stored property 設完之前不能呼叫實例方法，但可以呼叫它。
    static func mount(_ view: NSView & IconDrawing, on item: NSStatusItem) {
        item.length = view.preferredWidth + horizontalPadding * 2
        view.frame = NSRect(x: horizontalPadding, y: 0,
                            width: view.preferredWidth, height: NSStatusBar.system.thickness)
        item.button?.addSubview(view)
    }

    /// `IconShape.systemSymbolName` 非 nil 就建 `SFSymbolIconView`，否則（只剩 `.ledStrip`）
    /// 沿用既有 `LEDStripView`——回傳型別是 `NSView & IconDrawing`，呼叫端不必再 `as?` 轉型。
    static func makeDrawingView(for shape: IconShape) -> NSView & IconDrawing {
        if let symbolName = shape.systemSymbolName {
            let view = SFSymbolIconView()
            view.symbolName = symbolName
            return view
        }
        return LEDStripView()
    }

    /// D-2：造型只決定畫什麼形狀，appearance／phase 完全不碰——換造型後立刻用
    /// `lastAppearance` 重畫一次（否則新 view 在下一次動畫幀前是空的）；`showsPlate`
    /// 快取讓底板偏好延續，不會因為換造型回到每個 conformer各自的預設值。
    func setIconShape(_ shape: IconShape) {
        let view = Self.makeDrawingView(for: shape)
        view.setShowsPlate(showsPlate)
        (drawing as? NSView)?.removeFromSuperview()
        drawing = view
        Self.mount(view, on: item)
        drawing.update(lastAppearance, phase: 0)
    }
}
