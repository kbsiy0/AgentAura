import Testing
@testable import AgentAuraApp
import AuraCore

/// T26：`.setLanguage` 這個 G5 case 的驗證體，搬出主檔只是為了不撞
/// `AppDelegatePanelActionsWiredTests.swift` 的 300 行 Tests 上限——同 T12／T16 那幾個
/// case 的理由，沿用同一份 `withFreshRig`／`Rig`（同一個 test target，internal 可見）。
extension AppDelegatePanelActionsWiredTests {
    /// 兩個語言都要送（N7）；接線斷言分兩層——`delegate.language`（狀態本身）與
    /// `rig.spy.panels.last?.language`（真的轉發到面板 model，不是只改了旗標沒人看得到）。
    @MainActor
    func verifyLanguage(samples: [PanelAction]) async throws {
        try await withFreshRig { rig in
            #expect(samples.contains(.setLanguage(.english)) && samples.contains(.setLanguage(.traditionalChinese)),
                   "N7：兩個語言都要送，實際 \(samples)")
            #expect(rig.delegate.language == .english, "前提：D-2 預設應為 .english")
            for action in samples {
                guard case .setLanguage(let target) = action else { continue }
                rig.onAction(action)
                #expect(rig.delegate.language == target, "設完應更新 delegate.language，應為 \(target)")
                #expect(rig.spy.panels.last?.language == target, """
                    .setLanguage(\(target)) 應該轉發到面板 model，實際 \
                    \(String(describing: rig.spy.panels.last?.language))
                    """)
            }
        }
    }
}
