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

    /// T10：三個新 case 從 stub 換成真接線之後的驗證體——各自對準自己的真副作用，不是
    /// 共用一個「banner != nil」（T07 review m3：T10 之後任何 banner 都能滿足那條，函式
    /// 名也會變成謊言）。**`.copyCodexSnippet` 的真實副作用是寫剪貼簿、不一定設 banner**
    /// ——把斷言放寬成 `banner != nil` 是弱化，這裡對準注入縫 `pasteboardWrites`。
    @MainActor
    func verifyConnectCodex(samples: [PanelAction]) async throws {
        try await withFreshRig { rig in
            for action in samples { rig.onAction(action) }
            #expect(rig.recorder.fakeCodexInstaller.connectCallCount == 1,
                    ".connectCodex 應該讓注入的 fake 收到恰一次 connect()")
            let written = try #require(rig.recorder.fakeCodexInstaller.diskContents)
            #expect(rig.delegate.codexRuntime.store.contents == written, """
                CodexHookStore 讀回來的位元組應與 connect() 寫出去的逐位元組相等
                """)
            #expect(rig.delegate.banner?.kind == .codexConnected, """
                .connectCodex 成功後應顯示「已接上」banner，T13b 之後走它自己的 kind
                （D-v：不再沿用 `.connected`，才能有自己的退場條件），實際 \(String(describing: rig.delegate.banner?.kind))
                """)
        }
    }

    @MainActor
    func verifyDisconnectCodex(samples: [PanelAction]) async throws {
        try await withFreshRig { rig in
            // 前提：先接上一次，讓 disconnect 這一步有真的東西可拆（同 Claude 側 `.disconnect`
            // case 的既有形狀）。
            rig.onAction(.connectCodex)
            #expect(rig.recorder.fakeCodexInstaller.connectCallCount == 1, "前置條件失敗：先 connectCodex 一次應該成功")
            rig.delegate.banner = nil   // 清掉前置 connect 留下的 banner，只看這個動作自己的效果

            for action in samples { rig.onAction(action) }
            #expect(rig.recorder.fakeCodexInstaller.disconnectCallCount == 1,
                    ".disconnectCodex 應該讓注入的 fake 收到恰一次 disconnect()")
            #expect(rig.recorder.fakeCodexInstaller.diskContents == nil, "disconnect 成功後磁碟內容應清空")
            #expect(rig.delegate.banner?.kind == .disconnected, ".disconnectCodex 成功後應顯示「已移除」banner")
        }
    }

    @MainActor
    func verifyCopyCodexSnippet(samples: [PanelAction]) async throws {
        try await withFreshRig { rig in
            #expect(rig.delegate.codexRuntime.codexSnippet != nil, "前提：pathRejection == nil 時應該有 snippet 可複製")
            for action in samples { rig.onAction(action) }
            #expect(rig.recorder.pasteboardWrites.count == 1, ".copyCodexSnippet 應該真的寫進剪貼簿注入縫恰一次")
            #expect(rig.recorder.pasteboardWrites.last == rig.delegate.codexRuntime.codexSnippet, """
                寫進剪貼簿的內容應該就是 codexSnippet 本身
                """)
        }
    }
}
