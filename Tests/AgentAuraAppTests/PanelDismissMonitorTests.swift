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

    @Test("setPopoverPinned(true) 裝兩個 monitor；(false) 各移除一次；再 pin 一次能重裝")
    func controllerLifecycleInstallsAndRemoves() {
        var installCount = 0, removeCount = 0
        let monitor = PanelDismissMonitor(
            installGlobal: { _ in installCount += 1; return "g" as AnyObject },
            installLocal: { _ in installCount += 1; return "l" as AnyObject },
            remove: { _ in removeCount += 1 })
        let controller = StatusItemController(dismissMonitor: monitor)
        defer { controller.removeFromStatusBar() }
        controller.attachPopover()

        controller.setPopoverPinned(true)
        #expect(installCount == 2, "釘住時應該裝好 global／local 兩個 monitor，實際 \(installCount) 次")

        controller.setPopoverPinned(false)
        #expect(removeCount == 2, "解除釘住應該各移除一次，實際 \(removeCount) 次")

        controller.setPopoverPinned(true)
        #expect(installCount == 4, "再釘住一次應該能重裝，實際 \(installCount) 次")
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

        controller.setPopoverPinned(true)
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
