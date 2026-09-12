import AppKit

/// `setPopoverPinned` 本身住在這裡——理由同 `StatusItemController+IconFrame.swift`，純粹是
/// 為了不撞 200 行上限才拆檔，不是為了抽象邊界。
extension StatusItemController {
    /// D-i：改色期間釘住 popover。解除有兩條路徑——`ColorPickerCoordinator.onEnd`（色板真的
    /// 關掉）與 `togglePopover`（無條件回 `.transient`，切到別的 app 再回來不會卡住）。
    ///
    /// T20：`.semitransient` 只在「切到別的 app」時自動關閉——點擊「同一個 app 內、色板以外」
    /// 的地方完全不會關（實機回報），所以釘住期間額外裝 `PanelDismissMonitor` 自己接管關閉；
    /// 解除釘住（不論哪條路徑）就把它拆掉，避免留下全域 monitor。
    func setPopoverPinned(_ pinned: Bool) {
        popover.behavior = pinned ? .semitransient : .transient
        guard pinned else { dismissMonitor.stopIfNeeded(); return }
        dismissMonitor.startIfNeeded(
            shouldClose: { [weak self] event in
                guard let self else { return false }
                return PanelDismissPolicy.shouldClose(
                    clickedWindowNumber: event.windowNumber,
                    popoverWindowNumber: self.popover.contentViewController?.view.window?.windowNumber,
                    colorPanelWindowNumber: NSColorPanel.shared.isVisible ? NSColorPanel.shared.windowNumber : nil,
                    anchorWindowNumber: self.item.button?.window?.windowNumber)
            },
            onDismiss: { [weak self] in self?.popover.performClose(nil) }
        )
    }

    /// E14（/simplify 波次2，struct#C4）：`showPanel`／`togglePopover` 原本各寫一份
    /// 「fail-soft guard ＋ `popover.show` ＋ 開 ⌘Q monitor」（doc 標「共用同一份 guard」，
    /// 實際是拷貝）——抽出來之後兩處各自只留自己的額外前提。internal（原為 `private`）：
    /// 搬來這個檔案之後，`togglePopover`／`showPanel`（留在主檔）要能跨檔呼叫它。
    func presentPopover(from button: NSStatusBarButton) {
        // fail-soft（review-t01 I3）：沒有內容就別呼叫 `NSPopover.show`（否則整個行程被
        // NSException 殺掉）。
        guard popover.contentViewController != nil else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // B3：面板顯示期間監聽 ⌘Q（LSUIElement popover 收不到選單列 key equivalent）。
        quitMonitor.startIfNeeded { [weak self] in self?.onAction?(.quit) }
    }
}
