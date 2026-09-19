import Testing
@testable import AgentAuraApp
import AuraCore

/// T07：`.connectCodex`／`.disconnectCodex`／`.copyCodexSnippet` 這三個 G5 case 的驗證體，
/// 搬出主檔只是為了不撞 `AppDelegatePanelActionsWiredTests.swift` 的 300 行 Tests 上限——
/// 同 T16／T26／T32 那幾個 case 的理由，沿用同一份 `withFreshRig`／`Rig`（同一個 test
/// target，internal 可見）。
extension AppDelegatePanelActionsWiredTests {
    /// team-lead 裁決（AURA_CODEX_PENDING_T10）：`AppDelegate+PanelActions.swift` 的
    /// `switch action` 對這三個新 case 目前是暫時 stub（`break`）——T10 接線前，故意驗一個
    /// 現在會失敗的屬性（沒有任何 banner 出現），讓這條「每個 kind 都要有真副作用」的既有
    /// gate 對這三個新 kind 保持誠實地紅，而不是被繞過或標成通過（tested≠wired 的守衛正在
    /// 做它該做的事）。T10 接線後必須把這裡換成真的斷言（連上 `CodexInstaller`／
    /// `CodexHookStore` 之後的可觀察效果）。
    @MainActor
    func verifyCodexActionsAreStubbed(kind: PanelActionKind, samples: [PanelAction]) async throws {
        try await withFreshRig { rig in
            for action in samples { rig.onAction(action) }
            #expect(rig.delegate.banner != nil, """
                .\(kind) 目前是 stub（break），還沒有任何真副作用——T10 接線後這裡應該
                有 banner 或其他可觀察效果，暫時保持紅燈是正確的
                """)
        }
    }
}
