import Testing
import Foundation
@testable import AgentAuraApp
import AuraCore
import AuraHookFile

/// spec §4.4／§6.2（T08）：`firstRunOpensPanelOnce`／`firstRunOrdering`。
///
/// `applicationDidFinishLaunching` 是同步函式——`graph.start()` 的 `onIconStateChange`
/// 回呼一律經 `Task { @MainActor in … }` 派工，不會搶在函式返回前插隊。所以在
/// `applicationDidFinishLaunching(...)` 返回的**當下**（還沒讓出過任何 run loop）讀
/// `spy.callOrder`，量到的就是這個函式同步做過的事，不必等待或輪詢。
@MainActor
@Suite("首次啟動自動開面板（firstRunOpensPanelOnce／firstRunOrdering）", .serialized)
struct AppDelegateFirstRunTests {

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-firstrun-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func freshDefaults() throws -> (defaults: UserDefaults, suiteName: String) {
        let suite = "io.agentaura.tests.firstrun.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (defaults, suite)
    }

    @Test("!didConnectOnce && !connected（notConnected 的 claudeHome）→ showPanel() 恰一次，順序 attachPopover→setPanel→showPanel")
    func showsPanelOnceWhenNeverConnected() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let claudeHome = FileManager.default.temporaryDirectory.appendingPathComponent("aura-firstrun-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: claudeHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: claudeHome) }
        let installer = AppInstallerFixture.installer(claudeHome: claudeHome, bundlePluginURL: claudeHome)   // 不存在的掛載，notConnected

        let spy = SpyRenderer()
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   installer: installer, makeLoginItem: { FakeLoginItem() },
                                   codexDependencies: .inert(), makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        #expect(spy.showPanelCallCount == 1, "首次啟動、從沒接上過、目前也沒接上 → showPanel() 應恰好呼叫一次，實際 \(spy.showPanelCallCount) 次")
        #expect(Array(spy.callOrder.prefix(3)) == ["attachPopover", "setPanel", "showPanel"], """
            首啟順序應為 attachPopover → setPanel(真實狀態) → showPanel，實際 \(spy.callOrder.prefix(3))
            """)
    }

    @Test("didConnectOnce 旗標已設 → 即使目前沒接上，也不呼叫 showPanel()")
    func doesNotShowPanelWhenFlagAlreadySet() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AppDelegate.didConnectOnceKey)
        let claudeHome = FileManager.default.temporaryDirectory.appendingPathComponent("aura-firstrun-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: claudeHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: claudeHome) }
        let installer = AppInstallerFixture.installer(claudeHome: claudeHome, bundlePluginURL: claudeHome)

        let spy = SpyRenderer()
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   installer: installer, makeLoginItem: { FakeLoginItem() },
                                   codexDependencies: .inert(), makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        #expect(spy.showPanelCallCount == 0, "旗標已設（曾經接上過）不該再自動開面板，實際呼叫 \(spy.showPanelCallCount) 次")
    }

    @Test("目前已接上（即使旗標未設）→ 不呼叫 showPanel()")
    func doesNotShowPanelWhenCurrentlyConnected() throws {
        let layout = try AppInstallerFixture.make()
        defer { layout.cleanup() }
        try AppInstallerFixture.linkDirectly(layout)
        let installer = AppInstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let spy = SpyRenderer()
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   installer: installer, makeLoginItem: { FakeLoginItem() },
                                   codexDependencies: .inert(), makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        #expect(spy.showPanelCallCount == 0, "目前已接上不該自動開面板（即使旗標還沒設過），實際呼叫 \(spy.showPanelCallCount) 次")
    }
}
