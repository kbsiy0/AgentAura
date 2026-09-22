import Testing
import Foundation
import AppKit
@testable import AgentAuraApp
import AuraCore
import AuraHookFile

/// T21（panel-interaction-fixes，tested ≠ wired，Lessons #5）：`ColorPickerCoordinator.end()`
/// 的邏輯可以 100% 正確，而 `AppDelegate` 忘了在面板關閉時真的呼叫它——色板照樣變孤兒視窗。
/// 這條守的就是那一跳：真的 `AppDelegate`（不 mock `ColorPickerCoordinator`），走
/// `status.onClose`（`SpyRenderer.onClose`，`PaletteWiringSmokeTests` 已經證實這是
/// composition root 真的接給 `StatusItemController` 的同一個閉包）。
@MainActor
@Suite("面板關閉真的會關色板（T21 wiring）", .serialized)
struct ColorPanelCloseWiringTests {

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-t21-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func freshDefaults() throws -> (defaults: UserDefaults, suiteName: String) {
        let suite = "io.agentaura.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite), "建不出 suite \(suite)")
        return (defaults, suite)
    }

    /// (c) wiring gate：正在改色時，面板關閉（`spy.onClose?()`）真的會走到
    /// `colorCoordinator.end()` → 呼叫注入的 `closeColorPanel`。
    @Test("正在改色時，面板關閉會呼叫 colorCoordinator 的 closeColorPanel 恰一次")
    func panelCloseReachesColorCoordinatorEnd() throws {
        let spy = SpyRenderer()
        let (defaults, suiteName) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 60, defaults: defaults,
                                   confirmDisconnectCodex: { _, onConfirm in onConfirm() }, codexDependencies: .inert(), makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        var closeCalls = 0
        delegate.colorCoordinator.closeColorPanel = { closeCalls += 1 }
        delegate.colorCoordinator.pick(.waiting, current: RGBA(r: 0.1, g: 0.1, b: 0.1, a: 1), anchor: nil, present: false)

        let onClose = try #require(spy.onClose, "composition root 沒有接 status.onClose")
        onClose()

        #expect(closeCalls == 1, """
            面板關閉時正在改色，colorCoordinator 的 closeColorPanel 應該被呼叫恰一次，\
            實際 \(closeCalls) 次——色板會變成孤兒視窗（面板已經看不到，色板還浮著）。
            """)
    }

    /// (b) 對照組：沒在改色時，面板關閉不該多做事——同一條 gate 順便驗證 `end()` 的
    /// guard 有接上（不是 `AppDelegate` 端又額外判斷一次）。
    @Test("沒在改色時，面板關閉不呼叫 closeColorPanel")
    func panelCloseIsNoOpWhenNotPicking() throws {
        let spy = SpyRenderer()
        let (defaults, suiteName) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 60, defaults: defaults,
                                   confirmDisconnectCodex: { _, onConfirm in onConfirm() }, codexDependencies: .inert(), makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        var closeCalls = 0
        delegate.colorCoordinator.closeColorPanel = { closeCalls += 1 }
        // 刻意不呼叫 pick。

        let onClose = try #require(spy.onClose, "composition root 沒有接 status.onClose")
        onClose()

        #expect(closeCalls == 0, "沒在改色時面板關閉不該呼叫 closeColorPanel，實際 \(closeCalls) 次")
    }
}
