import Testing
import Foundation
import AppKit
@testable import AgentAuraApp

/// T20：`PanelDismissMonitor`——`QuitKeyMonitor` 的同形手足。(a) monitor 本身（注入的
/// install／remove、start/stop 冪等、global 恆關閉／local 交給 shouldClose）；
/// (b) `StatusItemController.setPopoverPinned` 的生命週期接線（釘住裝、解除／didClose 拆）。
@MainActor
@Suite("T20：面板釘住期間的滑鼠 monitor", .serialized)
struct PanelDismissMonitorTests {

    static func clickEvent(windowNumber: Int) -> NSEvent {
        NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                           windowNumber: windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    // MARK: - (a) PanelDismissMonitor 本身

    @Test("startIfNeeded：已經裝過就不重複裝兩個 monitor（global／local 各自冪等）")
    func startIfNeededIsIdempotent() {
        var globalCount = 0, localCount = 0
        let monitor = PanelDismissMonitor(
            installGlobal: { _ in globalCount += 1; return "g" as AnyObject },
            installLocal: { _ in localCount += 1; return "l" as AnyObject },
            remove: { _ in })
        monitor.startIfNeeded(shouldClose: { _ in false }, onDismiss: {})
        monitor.startIfNeeded(shouldClose: { _ in false }, onDismiss: {})
        monitor.startIfNeeded(shouldClose: { _ in false }, onDismiss: {})
        #expect(globalCount == 1, "重複呼叫不該重複裝 global monitor，實際 \(globalCount) 次")
        #expect(localCount == 1, "重複呼叫不該重複裝 local monitor，實際 \(localCount) 次")
    }

    @Test("stopIfNeeded：沒裝過是 no-op；裝過之後兩個 monitor 各移除一次；關掉後能再裝一次")
    func stopIfNeededIsIdempotentAndRestartable() {
        var removeCount = 0
        let monitor = PanelDismissMonitor(
            installGlobal: { _ in "g" as AnyObject }, installLocal: { _ in "l" as AnyObject },
            remove: { _ in removeCount += 1 })
        monitor.stopIfNeeded()
        #expect(removeCount == 0, "沒裝過就不該呼叫 remove")

        monitor.startIfNeeded(shouldClose: { _ in false }, onDismiss: {})
        monitor.stopIfNeeded()
        monitor.stopIfNeeded()
        #expect(removeCount == 2, "應該各移除 global／local 一次（重複呼叫不再增），實際 \(removeCount) 次")

        monitor.startIfNeeded(shouldClose: { _ in false }, onDismiss: {})
        #expect(removeCount == 2, "重新裝不該觸發 remove")
    }

    @Test("全域 monitor：任何事件都視為外部點擊，恆呼叫 onDismiss（別的 app，不需要再判斷）")
    func globalMonitorAlwaysDismisses() throws {
        var capturedGlobalHandler: ((NSEvent) -> Void)?
        let monitor = PanelDismissMonitor(
            installGlobal: { handler in capturedGlobalHandler = handler; return "g" as AnyObject },
            installLocal: { _ in "l" as AnyObject }, remove: { _ in })
        var dismissCount = 0
        monitor.startIfNeeded(shouldClose: { _ in false }, onDismiss: { dismissCount += 1 })
        let handler = try #require(capturedGlobalHandler)

        handler(Self.clickEvent(windowNumber: 42))
        #expect(dismissCount == 1, "全域 monitor 收到的事件必然是別的 app，該恆關，實際 \(dismissCount) 次")
    }

    @Test("本地 monitor：shouldClose 決定要不要呼叫 onDismiss；事件一律原樣傳回、不吞掉")
    func localMonitorDelegatesToShouldClose() throws {
        var capturedLocalHandler: ((NSEvent) -> NSEvent?)?
        let monitor = PanelDismissMonitor(
            installGlobal: { _ in "g" as AnyObject },
            installLocal: { handler in capturedLocalHandler = handler; return "l" as AnyObject },
            remove: { _ in })
        var dismissCount = 0
        var seenWindowNumbers: [Int] = []
        monitor.startIfNeeded(
            shouldClose: { event in seenWindowNumbers.append(event.windowNumber); return event.windowNumber == 7 },
            onDismiss: { dismissCount += 1 })
        let handler = try #require(capturedLocalHandler)

        let insideEvent = Self.clickEvent(windowNumber: 1)
        #expect(handler(insideEvent) === insideEvent, "不論關不關，事件都該原樣傳回，不能吞掉")
        #expect(dismissCount == 0, "shouldClose 回 false 不該呼叫 onDismiss")

        _ = handler(Self.clickEvent(windowNumber: 7))
        #expect(dismissCount == 1, "shouldClose 回 true 才呼叫 onDismiss，實際 \(dismissCount) 次")
        #expect(seenWindowNumbers == [1, 7], "shouldClose 應該收到事件本身（windowNumber 對得上）")
    }

    // MARK: - (b) StatusItemController 生命週期

    /// **T37 改寫（對齊新契約，不是弱化）。**
    ///
    /// 改寫前釘的是「釘住才裝、解除釘住就拆」。那個生命週期**本身就是使用者回報的 bug**：
    /// monitor 只在改色期間存在，平常完全沒裝，收起面板得靠 `.transient` 的系統行為——
    /// 而實機上點別的應用程式時面板不會收，使用者被迫回頭點選單列圖示。
    ///
    /// 新契約：monitor 的生命週期是**「面板顯示中」**，不是「改色中」。
    /// 釘住／解除釘住只換 `popover.behavior`，不再拆掉 monitor——收起的責任一路都在我們自己身上，
    /// 不是一半靠系統一半靠自己（那種形狀裡壞掉的永遠是沒人看顧的那一半）。
    ///
    /// 這條測的仍然是同一件事：**monitor 的裝與拆有沒有跟著它該跟的生命週期走**。
    /// 只是那個生命週期被修正了，所以斷言跟著改。拆除本身由下面那條
    /// `didClose` 的測試守（面板關閉才拆），兩條合起來涵蓋完整生命週期。
    /// altitude#3 之後再收一次：`setPopoverPinned` 不再有任何 monitor 副作用，所以這裡
    /// 改成直接呼叫 `startDismissMonitorIfNeeded()` 代表「面板已顯示」（離屏渲染下
    /// `popover.show` 恆無效，拿不到真正的顯示狀態），並把兩個方向的斷言都加強成
    /// 「釘住狀態怎麼變都不影響 monitor」。**斷言內容沒有變弱**，但也要誠實說它的極限：
    /// monitor 已經裝著時 `startIfNeeded` 是 no-op，所以這條抓不到「有人把裝設副作用加回
    /// `setPopoverPinned`」——那由下面 `pinningWithoutShownPanelInstallsNothing` 負責。
    @Test("面板顯示就裝兩個 monitor；釘住狀態怎麼變都不影響它（生命週期是「顯示中」不是「改色中」）")
    func controllerInstallsMonitorWhilePanelIsShown() {
        var installCount = 0, removeCount = 0
        let monitor = PanelDismissMonitor(
            installGlobal: { _ in installCount += 1; return "g" as AnyObject },
            installLocal: { _ in installCount += 1; return "l" as AnyObject },
            remove: { _ in removeCount += 1 })
        let controller = StatusItemController(dismissMonitor: monitor)
        defer { controller.removeFromStatusBar() }
        controller.attachPopover()

        controller.startDismissMonitorIfNeeded()          // ＝「面板顯示了」
        #expect(installCount == 2, "應該裝好 global／local 兩個 monitor，實際 \(installCount) 次")

        controller.setPopoverPinned(false)
        #expect(removeCount == 0, """
            解除釘住**不得**拆掉 monitor——面板還開著，點外面仍然要收得起來。
            拆掉它正是使用者回報的那個 bug，實際移除了 \(removeCount) 次
            """)

        controller.setPopoverPinned(true)
        #expect(installCount == 2 && removeCount == 0, """
            釘住狀態的變化不該裝也不該拆 monitor——它只換 `popover.behavior`。
            實際 install \(installCount) 次／remove \(removeCount) 次
            """)
    }

    /// altitude#3／efficiency#D 指出的實際風險路徑：`ColorPickerCoordinator` 的 `willClose`
    /// observer → `onEnd` → `setPopoverPinned(false)`，而那時**面板早就關了**。
    /// T37 到 altitude#3 之間，那條路徑會裝上一個沒有面板的全域滑鼠 monitor；它沒有真的
    /// 洩漏出去，唯一原因是 `didClose` handler 裡 `onClose?()` 剛好排在
    /// `dismissMonitor.stopIfNeeded()` 之前——**那兩行對調就會永久留下一個全域監看**
    /// （每一次全系統點擊都喚醒這個常駐行程）。靠語句順序維持的正確性不該只存在於記憶裡。
    ///
    /// **mutation**：把 `startDismissMonitorIfNeeded()` 加回 `setPopoverPinned`，這條變紅。
    @Test("面板沒顯示時改變釘住狀態，不得裝上任何 monitor（色板關閉走的正是這條路）")
    func pinningWithoutShownPanelInstallsNothing() {
        var installCount = 0
        let monitor = PanelDismissMonitor(
            installGlobal: { _ in installCount += 1; return "g" as AnyObject },
            installLocal: { _ in installCount += 1; return "l" as AnyObject },
            remove: { _ in })
        let controller = StatusItemController(dismissMonitor: monitor)
        defer { controller.removeFromStatusBar() }
        controller.attachPopover()

        controller.setPopoverPinned(true)
        controller.setPopoverPinned(false)
        #expect(installCount == 0, """
            面板沒顯示，卻裝了 \(installCount) 個全域滑鼠 monitor。
            `setPopoverPinned` 只該換 `popover.behavior`；裝拆 monitor 是
            `presentPopover`／`didClose` 那一對的責任。
            """)
    }

    @Test("popover 的 didClose 通知也會拆 monitor（不論是誰讓 popover 關的），不留下全域監看")
    func didCloseAlsoRemovesMonitor() {
        var removeCount = 0
        let monitor = PanelDismissMonitor(
            installGlobal: { _ in "g" as AnyObject }, installLocal: { _ in "l" as AnyObject },
            remove: { _ in removeCount += 1 })
        let controller = StatusItemController(dismissMonitor: monitor)
        defer { controller.removeFromStatusBar() }
        controller.attachPopover()

        // 前置：讓 monitor 處於「已裝」狀態。altitude#3 之後 `setPopoverPinned` 不再有這個
        // 副作用，所以改用它真正的裝設點（原本借釘住來裝，是這條測試的手段不是它的主題）。
        controller.startDismissMonitorIfNeeded()
        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: controller.popover)
        #expect(removeCount == 2, """
            popover 真的關掉時（不論是我們自己的 dismiss monitor 觸發 performClose，還是別的路徑），\
            應該連帶拆掉滑鼠監看，實際 \(removeCount) 次
            """)
    }

    @Test("別的 popover 關閉不該拆這個 controller 的 monitor（object 過濾）")
    func unrelatedPopoverCloseDoesNotRemove() {
        var removeCount = 0
        let monitor = PanelDismissMonitor(
            installGlobal: { _ in "g" as AnyObject }, installLocal: { _ in "l" as AnyObject },
            remove: { _ in removeCount += 1 })
        let controller = StatusItemController(dismissMonitor: monitor)
        defer { controller.removeFromStatusBar() }
        controller.attachPopover()
        controller.setPopoverPinned(true)

        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: NSPopover())
        #expect(removeCount == 0, "別的 popover 關閉不該影響這個 controller 的 dismiss monitor")
    }
}
