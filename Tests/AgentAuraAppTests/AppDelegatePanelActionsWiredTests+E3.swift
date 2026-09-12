import Testing
@testable import AgentAuraApp
import AuraCore

/// E3（/simplify 波次2，struct#E2）：`.openHelp` 這個 G5 case 的驗證體，搬出主檔只是為了
/// 不撞 `AppDelegatePanelActionsWiredTests.swift` 的 300 行 Tests 上限——同 T12／T16 那幾個
/// case 的理由，沿用同一份 `withFreshRig`／`Rig`（同一個 test target，internal 可見）。
extension AppDelegatePanelActionsWiredTests {
    /// `AppDelegate+PanelActions.helpURL()` 的 fallback 現在真的驗 `fileExists`——`swift test`
    /// 底下 `Bundle.main` 是 swiftpm 工具鏈本身的執行檔（實測：`Bundle.main.bundlePath` 落在
    /// Xcode 工具鏈的 `usr/libexec/swift/pm`），從來沒有 `help.html` 可拿。修好之前這裡的舊斷言
    /// （`openedURLs.last?.lastPathComponent == "help.html"`）能過，只是因為 fallback 不驗
    /// 存在性、無條件拼出一個指向不存在檔案的 URL——那正是 guard 空轉本身，不是真的驗證
    /// 「按下去會開對的檔案」。guard 現在有牙齒之後，這個沙盒環境沒有資源可開，`openHelp()`
    /// 應該正確地什麼都不做（production `.app` bundle 由 `scripts/build-app.sh` 複製
    /// `Resources/help.html` 進去，這裡驗不到那個路徑，是既有沙盒限制，不是這次改動造成的）。
    @MainActor
    func verifyOpenHelp(samples: [PanelAction]) async throws {
        try await withFreshRig { rig in
            for action in samples { rig.onAction(action) }
            #expect(rig.recorder.openedURLs.isEmpty, """
                這個沙盒環境沒有 help.html 資源，.openHelp 應該安全地什麼都不做，實際卻呼叫了 \
                openURL(\(String(describing: rig.recorder.openedURLs.last)))—— \
                代表 fail-soft guard 又變回空轉，拿一個指向不存在檔案的 URL 去開
                """)
        }
    }
}
