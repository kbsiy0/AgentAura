import Testing
import Foundation
import AppKit
@testable import AgentAuraApp
import AuraCore

/// T12（B1）：右鍵直接開 Options（快速路徑，footer 的「Options ⌄」主入口不受影響）。
/// 兩層驗證：(a) `StatusItemController.togglePopover()` 對右／左鍵的判別是否正確
/// （`currentEventType` 是注入的純函式風格判別點，不需要真的送一個 `NSEvent` 給 AppKit）；
/// (b) composition：`AppDelegate` 把 `onRightClick` 接成「強制展開＋重畫面板」，
/// 且不影響既有 `.toggleOptions` 那條路徑（由既有 G5 case 守，這裡不重複）。
@MainActor
@Suite("B1：右鍵直接開 Options", .serialized)
struct RightClickOpensOptionsTests {

    @Test("togglePopover()：右鍵時呼叫 onRightClick 一次")
    func rightClickTriggersCallback() {
        var count = 0
        let controller = StatusItemController(currentEventType: { .rightMouseUp })
        defer { controller.removeFromStatusBar() }
        controller.attachPopover()
        controller.onRightClick = { count += 1 }
        controller.togglePopover()
        #expect(count == 1, "右鍵應該觸發 onRightClick 恰一次，實際 \(count) 次")
    }

    @Test("togglePopover()：左鍵時不呼叫 onRightClick")
    func leftClickDoesNotTrigger() {
        var count = 0
        let controller = StatusItemController(currentEventType: { .leftMouseUp })
        defer { controller.removeFromStatusBar() }
        controller.attachPopover()
        controller.onRightClick = { count += 1 }
        controller.togglePopover()
        #expect(count == 0, "左鍵不該觸發 onRightClick，實際 \(count) 次")
    }

    @Test("togglePopover()：事件型別未知（nil）時視同左鍵，不觸發 onRightClick")
    func unknownEventTypeDoesNotTrigger() {
        var count = 0
        let controller = StatusItemController(currentEventType: { nil })
        defer { controller.removeFromStatusBar() }
        controller.attachPopover()
        controller.onRightClick = { count += 1 }
        controller.togglePopover()
        #expect(count == 0, "事件型別不明時不該誤判成右鍵，實際 \(count) 次")
    }

    @Test("togglePopover()：右鍵仍然照樣呼叫 onOpen——只是快速路徑，不取代既有開面板流程")
    func rightClickStillCallsOnOpen() {
        var opens = 0
        let controller = StatusItemController(currentEventType: { .rightMouseUp })
        defer { controller.removeFromStatusBar() }
        controller.attachPopover()
        controller.onOpen = { opens += 1 }
        controller.togglePopover()
        #expect(opens == 1, "右鍵不得跳過既有的 onOpen（reprobe＋setPanel），實際 \(opens) 次")
    }

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-rightclick-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// composition：`spy.onRightClick?()` 模擬「控制器判定為右鍵」之後，`AppDelegate`
    /// 接的動作是否正確——強制展開（不是 toggle）且重畫面板，不需要真的碰 `NSEvent`。
    @Test("composition：onRightClick 觸發後 optionsExpanded 變 true 且面板重畫反映它")
    func compositionForcesOptionsExpandedTrue() throws {
        let suite = "io.agentaura.tests.rightclick.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let spy = SpyRenderer()
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   makeLoginItem: { FakeLoginItem() },
                                   codexDependencies: .inert(), makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        #expect(delegate.optionsExpanded == false, "前提：預設收合")
        let onRightClick = try #require(spy.onRightClick, "AppDelegate 沒有接 status.onRightClick")
        onRightClick()

        #expect(delegate.optionsExpanded == true, "右鍵之後 optionsExpanded 應變 true")
        #expect(spy.panels.last?.optionsExpanded == true, "面板 model 也應反映展開狀態，不是只改了旗標沒人看得到")
    }

    /// 右鍵已經展開時再按一次仍是展開（強制設定，不是 toggle）——與 footer 那顆
    /// 「Options ⌄」的 `.toggleOptions`（會切換）語意刻意不同，見 `AppDelegate+PanelActions.swift`。
    @Test("composition：已展開時再次右鍵，仍維持展開（不是 toggle 成收合）")
    func compositionStaysExpandedOnRepeatedRightClick() throws {
        let suite = "io.agentaura.tests.rightclick2.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let spy = SpyRenderer()
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   makeLoginItem: { FakeLoginItem() },
                                   codexDependencies: .inert(), makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        let onRightClick = try #require(spy.onRightClick)
        onRightClick()
        onRightClick()
        #expect(delegate.optionsExpanded == true, "連續兩次右鍵仍應維持展開，實際 \(delegate.optionsExpanded)")
    }
}
