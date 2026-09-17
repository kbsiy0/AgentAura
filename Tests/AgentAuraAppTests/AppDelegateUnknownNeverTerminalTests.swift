import Testing
import Foundation
@testable import AgentAuraApp
import AuraCore
import AuraHookFile

/// `unknownIsNeverTerminal`（spec §6.2／R2）：exec 驗證的三種失敗——產物沒出現／逾時／
/// `Process.run()` 本身丟錯——**各自**都要寫回憑證；驗證跑完後狀態不得留在 `.unknown`。
/// `hookBlockedOrBroken`（產物沒出現）已由 `AppDelegateVerificationLifecycleTests` 覆蓋，
/// 這裡補另外兩種：spawn 丟錯（ENOEXEC）與逾時。
@MainActor
@Suite("背景驗證的三種失敗都不得留在 unknown（unknownIsNeverTerminal）", .serialized)
struct AppDelegateUnknownNeverTerminalTests {

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-unknownterminal-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func freshDefaults() throws -> (defaults: UserDefaults, suiteName: String) {
        let suite = "io.agentaura.tests.unknownterminal.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    @MainActor
    func wait(upTo seconds: TimeInterval, until cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if cond() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// spawn 本身丟錯（垃圾位元組、非法可執行格式，`Process.run()` 丟 ENOEXEC）
    /// → `.hookUnconfirmed`，不是 `.unknown`。
    @Test("spawn 丟錯（ENOEXEC）→ 最終寫回 hookUnconfirmed，不留在 unknown")
    func spawnThrowsEndsUpUnconfirmed() async throws {
        let layout = try AppInstallerFixture.makeWithUnexecutableGarbageBinary()
        defer { layout.cleanup() }
        try AppInstallerFixture.linkDirectly(layout)
        let installer = AppInstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin,
                                  verificationTimeout: 3)
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let spy = SpyRenderer()
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   installer: installer, makeLoginItem: { FakeLoginItem() }, makeRenderer: { spy })
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        // T10b：觸發＋輪詢整段一起經過 SpawnGate，理由同 AppDelegateVerificationLifecycleTests。
        //
        // 等待上限 60 秒（原本 10）：這是「願意等多久」的界限，不是斷言本身——斷言仍然是
        // 「最終必須是 hookUnconfirmed，不得停在 unknown」，一個字都沒改。10 秒在本機夠，
        // 在 CI runner 上不夠（2026-09-17 實測紅在 `connected(verified: .unknown)`，
        // 也就是背景驗證根本還沒跑完）。把一個負載相依的界限放寬，不等於放過壞掉的行為：
        // 真的卡住時這條仍然會紅，只是要多等 50 秒。
        await SpawnGate.shared.run {
            delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
            await wait(upTo: 60) {
                if case .broken(.hookUnconfirmed, _) = delegate.installState { return true }
                return false
            }
        }
        guard case .broken(.hookUnconfirmed, _) = delegate.installState else {
            Issue.record("spawn 丟錯之後應該是 broken(.hookUnconfirmed, _)，不是 unknown 或其他，實際 \(delegate.installState)")
            return
        }
    }

    /// 逾時（機器睡眠等，這裡用會跑超過有界等待的二進位模擬）→ `.hookUnconfirmed`，
    /// 且**不得**誤指控成 `.hookBlockedOrBroken`（S2-11：逾時與「產物確實沒出現」是兩種
    /// 寫回值，反過來寫會把「機器睡眠」永久誤指控成「macOS 擋住了 hook」）。
    @Test("逾時（跑超過有界等待）→ 最終寫回 hookUnconfirmed，不是 hookBlockedOrBroken")
    func timeoutEndsUpUnconfirmedNotBlocked() async throws {
        let layout = try AppInstallerFixture.makeWithSlowHookBinary()
        defer { layout.cleanup() }
        try AppInstallerFixture.linkDirectly(layout)
        // 短逾時（0.3s）：二進位跑 5 秒才結束，遠超過這個上限，測試不必真的等 5 秒。
        let installer = AppInstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin,
                                  verificationTimeout: 1)
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let spy = SpyRenderer()
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   installer: installer, makeLoginItem: { FakeLoginItem() }, makeRenderer: { spy })
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        await SpawnGate.shared.run {
            delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
            await wait(upTo: 60) {
                if case .broken(.hookUnconfirmed, _) = delegate.installState { return true }
                return false
            }
        }
        guard case .broken(.hookUnconfirmed, _) = delegate.installState else {
            Issue.record("逾時之後應該是 broken(.hookUnconfirmed, _)，實際 \(delegate.installState)——若是 hookBlockedOrBroken，代表逾時被誤指控成 macOS 擋住了 hook（S2-11）")
            return
        }
    }
}
