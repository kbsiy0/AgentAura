import Testing
import Foundation
@testable import AgentAuraApp
import AuraCore

/// T13j（S1-5，D-ac，CX57）：`codexDisconnectGoesThroughConfirmation`——`.disconnectCodex`
/// 先走確認框，比照 Claude 側 `.disconnect` 的既有注入縫（`confirmDisconnect`）第四個。
///
/// **注入的假身不得是「直接呼叫 onConfirm」**（T07 review m3 既有教訓的同一族）：否則
/// 「不確認 → 零副作用」這一格在任何實作下都成立。這裡兩格各自建一個獨立的
/// `AppDelegate`（不共用 `AppDelegatePanelActionsWiredTests.withFreshRig`——那份
/// harness 的預設假身**會**呼叫 `onConfirm`，服務的是「這個 action 有沒有真的接線」
/// 這個不同的問題，不適合拿來測「不確認時真的不動」）。
@MainActor
@Suite("`.disconnectCodex` 先走確認框才有副作用（CX57）", .serialized)
struct CodexDisconnectConfirmationTests {

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-codex-disconnect-confirm-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func freshDefaults() throws -> (defaults: UserDefaults, suiteName: String) {
        let suite = "io.agentaura.tests.codexdisconnectconfirm.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    /// 建一個已經連上 Codex 的 delegate（`.disconnectCodex` 有真的東西可拆），
    /// `confirmDisconnectCodex` 由呼叫端自己決定要不要呼叫 `onConfirm`。呼叫端負責
    /// `defer { defaults.removePersistentDomain(forName: suite) }`（同既有 helper 慣例）。
    func makeConnectedDelegate(confirmDisconnectCodex: @escaping @MainActor (Language, @escaping () -> Void) -> Void)
        throws -> (delegate: AppDelegate, spy: SpyRenderer, fakeInstaller: FakeCodexInstaller, defaults: UserDefaults, suite: String) {
        let (defaults, suite) = try freshDefaults()
        let spy = SpyRenderer()
        let fakeInstaller = FakeCodexInstaller(mode: .normal)
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   confirmDisconnectCodex: confirmDisconnectCodex,
                                   codexDependencies: CodexDependencies(installer: fakeInstaller, translocated: false,
                                                                        inDownloads: false, writeToPasteboard: { _ in },
                                                                        hookBinaryPath: AppDelegate.productionHookBinaryPath()),
                                   makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        let onAction = try #require(spy.onAction, "AppDelegate 沒有接 status.onAction")
        onAction(.connectCodex)
        #expect(fakeInstaller.connectCallCount == 1, "前置條件失敗：先 connectCodex 一次應該成功")
        return (delegate, spy, fakeInstaller, defaults, suite)
    }

    @Test("不確認（假身不呼叫 onConfirm）→ disconnectCallCount == 0，憑證鍵位元組不變")
    func doesNotDisconnectWithoutConfirmation() throws {
        let (delegate, spy, fakeInstaller, defaults, suite) = try makeConnectedDelegate(confirmDisconnectCodex: { _, _ in
            // 刻意不呼叫 onConfirm——模擬使用者按了「取消」。
        })
        defer {
            delegate.applicationWillTerminate(Notification(name: .init("test")))
            defaults.removePersistentDomain(forName: suite)
        }
        let onAction = try #require(spy.onAction)

        let credentialBefore = delegate.codexRuntime.store.contents
        let diskBefore = fakeInstaller.diskContents
        #expect(credentialBefore != nil, "前提：connect 之後應該有憑證可比對")

        onAction(.disconnectCodex)

        #expect(fakeInstaller.disconnectCallCount == 0, """
            確認框沒有被確認，disconnect() 不該被呼叫，實際呼叫次數 \(fakeInstaller.disconnectCallCount)
            """)
        #expect(delegate.codexRuntime.store.contents == credentialBefore, """
            確認框沒有被確認，憑證鍵應該逐位元組不變，實際 \(String(describing: delegate.codexRuntime.store.contents))
            """)
        #expect(fakeInstaller.diskContents == diskBefore, "確認框沒有被確認，磁碟內容應該逐位元組不變")
    }

    @Test("確認（假身呼叫 onConfirm）→ disconnectCallCount == 1")
    func disconnectsAfterConfirmation() throws {
        let (delegate, spy, fakeInstaller, defaults, suite) = try makeConnectedDelegate(confirmDisconnectCodex: { _, onConfirm in
            onConfirm()
        })
        defer {
            delegate.applicationWillTerminate(Notification(name: .init("test")))
            defaults.removePersistentDomain(forName: suite)
        }
        let onAction = try #require(spy.onAction)

        onAction(.disconnectCodex)

        #expect(fakeInstaller.disconnectCallCount == 1, """
            確認框被確認，disconnect() 應該恰好被呼叫一次，實際 \(fakeInstaller.disconnectCallCount)
            """)
        #expect(delegate.codexRuntime.store.contents == nil, "確認後 disconnect 成功，憑證鍵應該清空")
    }

    /// 文案必須點名 agent（對照既有 `L10nConfirmationAlerts.disconnectTitle` 已經點名
    /// Claude Code 的既有形狀）——標題／內文／確認鈕三句合起來至少要有一處含
    /// `Agent.codex.label!`。
    @Test("確認框文案含 Agent.codex.label！（點名是哪一側）", arguments: Language.allCases)
    func copyNamesTheAgent(language: Language) {
        let title = L10nConfirmationAlerts.disconnectCodexTitle.text(language)
        let body = L10nConfirmationAlerts.disconnectCodexBody.text(language)
        let confirmButton = L10nConfirmationAlerts.disconnectCodexConfirmButton.text(language)
        let all = [title, body, confirmButton].joined(separator: "\u{0}")
        #expect(all.contains(Agent.codex.label!), """
            確認框三句文案合起來應該至少一處含「\(Agent.codex.label!)」，實際：
            title="\(title)"，body="\(body)"，confirmButton="\(confirmButton)"
            """)
    }
}
