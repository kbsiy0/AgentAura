import Testing
@testable import AgentAuraApp
import AuraCore

/// T07：`.connectCodex`／`.disconnectCodex`／`.copyCodexSnippet` 這三個 G5 case 的驗證體，
/// 搬出主檔只是為了不撞 `AppDelegatePanelActionsWiredTests.swift` 的 300 行 Tests 上限——
/// 同 T16／T26／T32 那幾個 case 的理由，沿用同一份 `withFreshRig`／`Rig`（同一個 test
/// target，internal 可見）。
///
/// **T10 commit1（純搬移）**：把 `.replaceExternalMount`／`.quit` 這兩個既有 case 的驗證體
/// 也搬進來，替本檔接下來要新增的 CX24／CX25／CX26／CX31／CX35／CX39／CX40／CX42 斷言
/// 在主檔的 300 行上限裡留出餘裕——同 `+T12.swift` 把 `.about`／`.reportIssue`／
/// `.setReduceMotion` 三個互不相關的 case 收在同一個「依任務號」的擴充檔的既有先例，
/// 不是每個擴充檔都得跟自己的 case 同名。**逐字搬移，零行為變更**：body 內容原封不動，
/// 只是從主檔的 `switch` 分支換成這裡的具名函式。
extension AppDelegatePanelActionsWiredTests {
    /// 原本是 `everyActionKindHasARealWiredEffect` 裡 `.replaceExternalMount` 的 inline body
    /// （純搬移，見上方檔案 doc comment）。
    @MainActor
    func verifyReplaceExternalMount(samples: [PanelAction]) async throws {
        try await withFreshRig { rig in
            // 明確的前置條件：先 connect 一次，再送 replaceExternalMount，斷言只看
            // 第二次的效果——不依賴迴圈裡上一個 case 有沒有跑過、跑得快不快（T10b bug B）。
            await SpawnGate.shared.run { rig.onAction(.connect) }
            guard case .connected(.thisApp, .verified) = rig.delegate.installState else {
                Issue.record("前置條件失敗：先 connect 一次應該成功，實際 \(rig.delegate.installState)")
                return
            }
            rig.delegate.banner = nil   // 清掉前置 connect 留下的 banner，只看這個動作自己的效果
            await SpawnGate.shared.run {
                for action in samples { rig.onAction(action) }
            }
            // A5（T11 commit3）：確認框先擋一次——沒有這條，直接執行的 mutation 不會被抓到。
            #expect(rig.recorder.confirmedReplaceExternalMounts == 1, ".replaceExternalMount 應該先走過確認對話框閉包")
            #expect(rig.delegate.banner?.kind == .alreadyConnected, """
                對已接上的掛載送 .replaceExternalMount 應該早退成 .alreadyConnected banner，
                實際 \(String(describing: rig.delegate.banner?.kind))
                """)
        }
    }

    /// 原本是 `everyActionKindHasARealWiredEffect` 裡 `.quit` 的 inline body（純搬移，同上）。
    @MainActor
    func verifyQuit(samples: [PanelAction]) async throws {
        try await withFreshRig { rig in
            for action in samples { rig.onAction(action) }
            #expect(rig.recorder.fakeTerminator.terminateCallCount == 1, ".quit 應該呼叫注入的 terminator.terminate() 一次")
        }
    }

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
