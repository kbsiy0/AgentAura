import Testing
import Foundation
import AppKit
@testable import AgentAuraApp
import AuraCore

/// T12（B3）：Options 列上印著「離開 AgentAura ⌘Q」，但改之前按下去什麼都不會發生——
/// 這是誠實性問題（同 tooltip／CTA 說謊的病族），不是加分項。三層驗證：
/// (a) `QuitKeyMonitor` 本身（install／remove 的注入閉包、`isCommandQ` 判別）；
/// (b) `StatusItemController` 的生命週期接線（面板開→裝一次、關→移除一次）；
/// (c) composition：真的按下 ⌘Q 會走到注入的 `terminator`（不是真的 `NSApp.terminate`）。
@MainActor
@Suite("B3：⌘Q 監聽器", .serialized)
struct QuitKeyMonitorTests {

    static func commandQEvent() -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                         windowNumber: 0, context: nil, characters: "q", charactersIgnoringModifiers: "q",
                         isARepeat: false, keyCode: 12)!
    }

    static func plainAEvent() -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                         windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a",
                         isARepeat: false, keyCode: 0)!
    }

    // MARK: - (a) QuitKeyMonitor 本身

    @Test("isCommandQ：⌘Q 為 true，其餘（無修飾鍵的 a、⌘A）為 false")
    func isCommandQClassifiesCorrectly() {
        #expect(QuitKeyMonitor.isCommandQ(Self.commandQEvent()) == true)
        #expect(QuitKeyMonitor.isCommandQ(Self.plainAEvent()) == false)
        let commandA = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                        windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a",
                                        isARepeat: false, keyCode: 0)!
        #expect(QuitKeyMonitor.isCommandQ(commandA) == false, "⌘A 不是 ⌘Q")
    }

    @Test("startIfNeeded：已經裝過就不重複裝（面板開著時多次呼叫是 no-op）")
    func startIfNeededIsIdempotent() {
        var installCount = 0
        let monitor = QuitKeyMonitor(install: { _ in installCount += 1; return "token" as AnyObject }, remove: { _ in })
        monitor.startIfNeeded(onQuit: {})
        monitor.startIfNeeded(onQuit: {})
        monitor.startIfNeeded(onQuit: {})
        #expect(installCount == 1, "重複呼叫 startIfNeeded 不該重複裝 monitor，實際裝了 \(installCount) 次")
    }

    @Test("stopIfNeeded：沒裝過時呼叫是 no-op；裝過之後只移除一次")
    func stopIfNeededIsIdempotent() {
        var removeCount = 0
        let monitor = QuitKeyMonitor(install: { _ in "token" as AnyObject }, remove: { _ in removeCount += 1 })
        monitor.stopIfNeeded()
        #expect(removeCount == 0, "沒裝過就不該呼叫 remove")

        monitor.startIfNeeded(onQuit: {})
        monitor.stopIfNeeded()
        monitor.stopIfNeeded()
        #expect(removeCount == 1, "重複呼叫 stopIfNeeded 不該重複移除，實際移除了 \(removeCount) 次")
    }

    @Test("裝過一次、關掉、再裝一次：install 恰好兩次（不是永久卡在裝過一次就不再裝）")
    func canRestartAfterStop() {
        var installCount = 0
        let monitor = QuitKeyMonitor(install: { _ in installCount += 1; return "token" as AnyObject }, remove: { _ in })
        monitor.startIfNeeded(onQuit: {})
        monitor.stopIfNeeded()
        monitor.startIfNeeded(onQuit: {})
        #expect(installCount == 2, "關閉後應該能再裝一次（面板關了又開），實際 \(installCount) 次")
    }

    @Test("收到 ⌘Q：呼叫 onQuit 一次且吞掉事件（handler 回 nil）；其餘按鍵原樣傳回、不呼叫 onQuit")
    func handlerFiresOnCommandQAndPassesThroughOtherwise() throws {
        var capturedHandler: ((NSEvent) -> NSEvent?)?
        let monitor = QuitKeyMonitor(install: { handler in capturedHandler = handler; return "token" as AnyObject },
                                     remove: { _ in })
        var quitCount = 0
        monitor.startIfNeeded(onQuit: { quitCount += 1 })
        let handler = try #require(capturedHandler)

        let plain = Self.plainAEvent()
        #expect(handler(plain) === plain, "非 ⌘Q 的按鍵應該原樣傳回（讓別的 responder 照樣收到）")
        #expect(quitCount == 0)

        let result = handler(Self.commandQEvent())
        #expect(result == nil, "⌘Q 應該被吞掉，不再往下傳")
        #expect(quitCount == 1, "⌘Q 應該觸發 onQuit 恰一次")
    }

    // MARK: - (b) StatusItemController 生命週期

    @Test("面板開啟時裝一次 monitor，didClose 通知後移除一次（不論誰關的）")
    func controllerLifecycleInstallsAndRemoves() {
        var installCount = 0, removeCount = 0
        let monitor = QuitKeyMonitor(install: { _ in installCount += 1; return "token" as AnyObject },
                                     remove: { _ in removeCount += 1 })
        let controller = StatusItemController(quitMonitor: monitor)
        defer { controller.removeFromStatusBar() }
        controller.attachPopover()

        controller.togglePopover()
        #expect(installCount == 1, "面板開啟時應該裝一次 monitor，實際 \(installCount) 次")

        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: controller.popover)
        #expect(removeCount == 1, "面板關閉時應該移除 monitor 一次，實際 \(removeCount) 次")
    }

    @Test("別的 popover 關閉不該移除這個 controller 的 monitor（object 過濾）")
    func unrelatedPopoverCloseDoesNotRemove() {
        var removeCount = 0
        let monitor = QuitKeyMonitor(install: { _ in "token" as AnyObject }, remove: { _ in removeCount += 1 })
        let controller = StatusItemController(quitMonitor: monitor)
        defer { controller.removeFromStatusBar() }
        controller.attachPopover()
        controller.togglePopover()

        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: NSPopover())
        #expect(removeCount == 0, "別的 popover 關閉不該影響這個 controller 的 monitor")
    }

    // MARK: - (c) composition：真的按下 ⌘Q 走到注入的 terminator

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-quitkey-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("composition：面板開啟後收到 ⌘Q，注入的 terminator 被呼叫一次（不是真的 NSApp.terminate）")
    func compositionRoutesCommandQToInjectedTerminator() throws {
        var capturedHandler: ((NSEvent) -> NSEvent?)?
        let monitor = QuitKeyMonitor(install: { handler in capturedHandler = handler; return "token" as AnyObject },
                                     remove: { _ in })
        let controller = StatusItemController(quitMonitor: monitor)
        let fakeTerminator = FakeTerminator()
        let suite = "io.agentaura.tests.quitkey.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   makeLoginItem: { FakeLoginItem() }, terminator: fakeTerminator,
                                   codexDependencies: .inert(), makeRenderer: { controller })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer {
            delegate.applicationWillTerminate(Notification(name: .init("test")))
            controller.removeFromStatusBar()
        }

        controller.togglePopover()   // 開面板：裝 monitor、捕捉真正的 handler
        let handler = try #require(capturedHandler, "面板開啟後應該裝好 monitor")
        _ = handler(Self.commandQEvent())

        #expect(fakeTerminator.terminateCallCount == 1, """
            面板顯示期間收到 ⌘Q，應該經 onAction(.quit) 走到注入的 terminator，實際呼叫 \(fakeTerminator.terminateCallCount) 次
            """)
    }
}
