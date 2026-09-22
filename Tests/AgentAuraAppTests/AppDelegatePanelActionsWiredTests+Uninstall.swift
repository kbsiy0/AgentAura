import Testing
import Foundation
@testable import AgentAuraApp
import AuraCore

/// T24：`.uninstall` 這個 G5 case 的驗證體，搬出主檔只是為了不撞 300 行 Tests 上限——同
/// T12／T16 那幾個 case 的理由，沿用同一份 `withFreshRig`／`Rig`。
///
/// 這裡只驗**接線**：確認框先擋一次、真的停掉 liveness timer、真的呼叫
/// `loginItem.set(false)`、真的 `disconnect()`、最後真的呼叫注入的
/// `terminator.terminateImmediately()`——`Bundle.main.bundleIdentifier`／`bundleURL`
/// 在 `swift test` 下天生是 nil（`AppDelegate.performUninstall` 的既有判斷），所以這條
/// 不會真的碰 UserDefaults persistent domain 或呼叫 `NSWorkspace.recycle`；那兩步的
/// 正確性由 `UninstallerTests`（直接建構 `Uninstaller`，注入假 bundleIdentifier／假
/// recycler）獨立驗證。
extension AppDelegatePanelActionsWiredTests {
    @MainActor
    func verifyUninstall(samples: [PanelAction]) async throws {
        try await withFreshRig { rig in
            // 前提：先連上一次，讓 disconnect 這一步有真的東西可拆。
            await SpawnGate.shared.run { rig.onAction(.connect) }
            guard case .connected(.thisApp, .verified) = rig.delegate.installState else {
                Issue.record("前置條件失敗：先 connect 一次應該成功，實際 \(rig.delegate.installState)")
                return
            }
            // review M2：Codex 側也要先有真的東西可拆，否則下面的 disconnectCallCount／
            // store.contents 斷言測不到「performUninstall() 真的把 codexRuntime.installer／
            // store 傳進 Uninstaller(...)」這件事——生產呼叫點（AppDelegate+Connect.swift）
            // 的兩個新參數目前沒有任何 gate 守，這是唯一的接線測試。
            rig.onAction(.connectCodex)
            #expect(rig.recorder.fakeCodexInstaller.connectCallCount == 1, "前置條件失敗：先 connectCodex 一次應該成功")
            let loginItemSetCountBefore = rig.recorder.fakeLoginItem.setCallCount

            for action in samples { rig.onAction(action) }

            #expect(rig.recorder.confirmedUninstalls == 1, ".uninstall 應該先走過確認對話框閉包")
            #expect(rig.recorder.fakeLoginItem.setCallCount == loginItemSetCountBefore + 1, """
                .uninstall 應該呼叫 loginItem.set(false)（取消登入項目），實際呼叫次數沒有增加
                """)
            #expect(rig.recorder.fakeLoginItem.isEnabled == false, "取消登入項目之後 isEnabled 應為 false")
            // 直接看檔案系統，不是 `rig.delegate.installState`（後者只在呼叫 `reprobe()` 後
            // 才更新，而 `performUninstall()` 不呼叫它——app 反正緊接著就終止，重畫面板沒有
            // 意義）；「掛載真的被移除」是檔案系統事實，這才是 `installer.disconnect()`
            // 真的被呼叫到的證據。
            #expect(!FileManager.default.fileExists(
                atPath: rig.layout.claudeHome.appendingPathComponent("skills/agentaura").path),
                    ".uninstall 應該連帶移除掛載")
            // team-lead 真機實測抓到的殘留根因：liveness timer 沒停，在 recycle 的非同步
            // 等待期間醒來把剛刪的狀態目錄建回來。這裡直接斷言它被停掉——不是看副作用
            // （目錄有沒有回來要等 FSEvents／計時器真的跑一輪才驗得到，太慢也太間接）。
            #expect(rig.delegate.livenessTimer == nil, ".uninstall 應該在動手之前就停掉 liveness timer")
            #expect(rig.recorder.fakeTerminator.terminateImmediatelyCallCount == 1, """
                .uninstall 最後應該呼叫注入的 terminator.terminateImmediately() 一次（不是 terminate()——
                那條會經過 NSApp 的 teardown，team-lead 真機實測抓到它把剛清空的 defaults 寫回去）。
                bundleURL 在 swift test 下是 nil，走的是「沒東西可搬垃圾桶、直接終止」那條分支。
                """)
            // review M2：唯一守住「performUninstall() 真的把 codexRuntime.installer／store
            // 傳進 Uninstaller(...)」這件事的斷言——這是本次 review 新開的 tested≠wired 面。
            #expect(rig.recorder.fakeCodexInstaller.disconnectCallCount == 1, """
                .uninstall 應該連帶呼叫 Codex 側的 disconnect(ifContentsEqual:) 一次，\
                否則完整移除不移除 Codex hook（verify-uninstall.sh 第 7 項的實機情境）
                """)
            // **不用 `codexRuntime.store.contents == nil`**：`Uninstaller.run()` 靠
            // `erasePersistentDomain()`（不是額外呼叫 `codexStore.clear()`）連帶清空整個
            // persistent domain，但這條路徑在 `swift test` 下因為 `bundleIdentifier == nil`
            // 天生跳過（同既有 `skipsDefaultsErasureWhenBundleIdentifierNil` 驗證的那個早退），
            // 那樣斷言在這個 rig 裡永遠假。用 fake 自己的 `diskContents` 驗證
            // `disconnect(ifContentsEqual:)` 真的用「相符的內容」被呼叫、真的清空成功——
            // 傳錯 store 或內容不符時，fake 會 throw 而不清空，這裡才測得到。
            #expect(rig.recorder.fakeCodexInstaller.diskContents == nil, """
                .uninstall 之後 fake 的磁碟內容應該被清空——disconnect(ifContentsEqual:) 若收到
                不相符的 store（傳錯物件）會 throw 而不清空，這裡才測得到「傳的是同一個 store」
                """)
        }
    }
}
