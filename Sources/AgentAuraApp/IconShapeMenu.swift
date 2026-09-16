import AppKit
import AuraCore

/// T32：`.setIconShape` 觸發時開啟的造型選單（design doc D-1，比照 Amphetamine 的
/// Menu Bar Image 選單）——真的彈 `NSMenu`，選中項打勾（`current`）。同
/// `DisconnectConfirmation` 的注入縫（測試不真的彈選單，spec §6.4）。
///
/// `NSMenu.popUp(positioning:at:in:)` 是同步呼叫，回傳前使用者已經做出選擇或取消——
/// `Target` 只需要在這次呼叫期間存活，區域變數的生命週期已經足夠，不必是持久物件
/// （不像 `ColorPickerCoordinator` 要跨越色板開啟到關閉的整段非同步期間）。
@MainActor
enum IconShapeMenu {
    /// `appearance`／`showsPlate` 只為了畫縮圖——**挑造型要看得到造型**
    /// （使用者回報：「不要讓人選完才知道長什麼樣」）。縮圖由 `IconShapePreview`
    /// 用真正的繪製器產生，不是另外畫一份示意圖，所以不可能跟選單列上的實際長相漂開。
    static func present(current: IconShape, language: Language,
                        appearance: IconAppearance, showsPlate: Bool,
                        onSelect: @escaping (IconShape) -> Void) {
        let target = Target(onSelect: onSelect)
        let menu = NSMenu()
        let previewAppearance = appearance.staticFullyOpaque
        var animatedItems: [(shape: IconShape, item: NSMenuItem)] = []
        for shape in IconShape.allCases {
            let item = NSMenuItem(title: shape.displayName(language), action: #selector(Target.selected(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = shape
            item.state = shape == current ? .on : .off
            item.image = IconShapePreview.image(for: shape, appearance: previewAppearance, showsPlate: showsPlate)
            menu.addItem(item)
            animatedItems.append((shape, item))
        }
        // T35：選單開著時讓縮圖動起來（`IconShapeMenuPreview`），關閉後立刻停——
        // `popUp` 是阻塞呼叫，回傳當下選單已經真的關了，這裡不需要 didClose 之類的回呼。
        let preview = IconShapeMenuPreview(items: animatedItems, appearance: appearance, showsPlate: showsPlate)
        preview.start()
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        preview.stop()
    }

    /// `NSMenuItem` 的 target-action 只吃 `@objc` 方法，enum 不能是 target——包一個最小的
    /// `NSObject` 轉發到閉包，同 `ColorPickerCoordinator.changeColor(_:)` 的既有理由。
    @MainActor
    private final class Target: NSObject {
        let onSelect: (IconShape) -> Void
        init(onSelect: @escaping (IconShape) -> Void) { self.onSelect = onSelect }
        @objc func selected(_ sender: NSMenuItem) {
            guard let shape = sender.representedObject as? IconShape else { return }
            onSelect(shape)
        }
    }
}
