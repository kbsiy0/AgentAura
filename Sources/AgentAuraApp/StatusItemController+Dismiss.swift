import AppKit

/// `setPopoverPinned` 本身住在這裡——理由同 `StatusItemController+IconFrame.swift`，純粹是
/// 為了不撞 200 行上限才拆檔，不是為了抽象邊界。
extension StatusItemController {
    /// D-i：改色期間釘住 popover。解除有兩條路徑——`ColorPickerCoordinator.onEnd`（色板真的
    /// 關掉）與 `togglePopover`（無條件回 `.transient`，切到別的 app 再回來不會卡住）。
    ///
    /// T20：`.semitransient` 只在「切到別的 app」時自動關閉——點擊「同一個 app 內、色板以外」
    /// 的地方完全不會關（實機回報）。
    ///
    /// **這個函式只設 `behavior`，不碰 monitor**（`/simplify` icon-shapes 波次，altitude#3）。
    /// T20 當初在這裡裝／拆 monitor，T37 改成不拆但仍然裝——於是一個名字叫「設定釘住狀態」
    /// 的函式帶著跟名字無關的副作用，而 monitor 的負責人從一個變成兩個。那正是 T37
    /// 自己想修掉的形狀。實際風險不是理論的：`ColorPickerCoordinator.onEnd` 會在**面板
    /// 早已關閉**的情況下呼叫 `setPopoverPinned(false)`，目前沒漏掉只是因為 `didClose`
    /// handler 裡 `onClose?()` 剛好排在 `dismissMonitor.stopIfNeeded()` 之前——那兩行對調
    /// 就會留下一個永遠活著的全域滑鼠 monitor。
    ///
    /// monitor 的生命週期完全由 `presentPopover`（裝）與 `didClose`（拆）這一對決定。
    func setPopoverPinned(_ pinned: Bool) {
        popover.behavior = pinned ? .semitransient : .transient
    }

    /// T37：**面板一顯示就裝**，不再只在改色期間裝。
    ///
    /// 使用者回報「游標移開面板去點其他應用程式，面板沒有收起來」——T20 當初只在
    /// `setPopoverPinned(true)`（改色）時裝這個 monitor，平常完全不裝，靠 `.transient`
    /// 的系統預設行為。那個行為在 `LSUIElement` app 上不可靠：實機上點別的應用程式時
    /// 面板留在原地，使用者被迫回頭點選單列圖示。
    ///
    /// 既然我們已經有一份自己判斷的 `PanelDismissPolicy`（三個安全區：面板內／色板內／
    /// 選單列圖示），就一路用它，不要一半靠系統一半靠自己——那正是「同一件事有兩個負責人」
    /// 的壞形狀，而壞掉的永遠是沒人看顧的那一半。
    ///
    /// 唯一的生產呼叫點是 `presentPopover`（在 `popover.show` 之後）。這裡刻意**不**加
    /// `guard popover.isShown` 這種自我保護：離屏渲染下 `popover.show` 恆無效，加了之後
    /// 這條路徑就再也測不到，而它換來的安全是「防止我們自己從別的地方亂呼叫」——
    /// 那該由呼叫點只有一個來保證，不是由被呼叫的一方猜。
    func startDismissMonitorIfNeeded() {
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
        // T37：面板顯示期間一律自己負責「點外面就收起」，不靠 `.transient` 的系統行為。
        startDismissMonitorIfNeeded()
    }
}
