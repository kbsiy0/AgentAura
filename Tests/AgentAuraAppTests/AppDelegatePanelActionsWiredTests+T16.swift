import Testing
@testable import AgentAuraApp
import AuraCore

/// T16：`.setIconPlate` 這個 G5 case 的驗證體，搬出主檔只是為了不撞
/// `AppDelegatePanelActionsWiredTests.swift` 的 300 行 Tests 上限——同 T12 那三個 case
/// 的理由，沿用同一份 `withFreshRig`／`Rig`（同一個 test target，internal 可見）。
extension AppDelegatePanelActionsWiredTests {
    /// 兩個布林都要送（N7）；接線斷言分兩層——`delegate.iconPlate`（狀態本身）與
    /// `spy.iconPlateValues.last`（真的轉發到 `drawing`，不是只改了旗標沒人看得到）。
    @MainActor
    func verifySetIconPlate(samples: [PanelAction]) async throws {
        try await withFreshRig { rig in
            #expect(samples.contains(.setIconPlate(true)) && samples.contains(.setIconPlate(false)),
                   "N7：兩個布林都要送，實際 \(samples)")
            #expect(rig.delegate.iconPlate == true, "前提：預設應為 true")
            for action in samples {
                guard case .setIconPlate(let on) = action else { continue }
                rig.onAction(action)
                #expect(rig.spy.iconPlateValues.last == on, """
                    .setIconPlate(\(on)) 應該轉發到 drawing（spy.setIconPlate），\
                    實際 \(String(describing: rig.spy.iconPlateValues.last))
                    """)
                #expect(rig.delegate.iconPlate == on, "設完應更新 delegate.iconPlate，應為 \(on)")
            }
        }
    }
}
