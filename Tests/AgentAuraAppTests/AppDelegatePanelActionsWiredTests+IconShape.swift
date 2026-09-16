import Testing
@testable import AgentAuraApp
import AuraCore

/// T32：`.pickIconShape` 這個 G5 case 的驗證體，搬出主檔只是為了不撞
/// `AppDelegatePanelActionsWiredTests.swift` 的 300 行 Tests 上限——同 T16／T26 那幾個
/// case 的理由，沿用同一份 `withFreshRig`／`Rig`（同一個 test target，internal 可見）。
extension AppDelegatePanelActionsWiredTests {
    /// `IconShape.allCases` 每個都要送（N7）；接線斷言分三層——`recorder.presentedIconShapeMenuCount`
    /// （選單呈現閉包真的被呼叫，不是跳過那一步）、`delegate.iconShape`（狀態本身）、
    /// `spy.iconShapes.last`（真的轉發到 `status`，不是只改了旗標沒人看得到）。
    @MainActor
    func verifyIconShape(samples: [PanelAction]) async throws {
        try await withFreshRig { rig in
            for shape in IconShape.allCases {
                #expect(samples.contains(.pickIconShape(shape)), "N7：IconShape.allCases 每個都要送，缺 \(shape)")
            }
            #expect(rig.delegate.iconShape == .ledStrip, "前提：D-3 預設應為 .ledStrip")
            for action in samples {
                guard case .pickIconShape(let shape) = action else { continue }
                let before = rig.recorder.presentedIconShapeMenuCount
                rig.onAction(action)
                #expect(rig.recorder.presentedIconShapeMenuCount == before + 1,
                       ".pickIconShape(\(shape)) 應該先走過選單呈現閉包")
                #expect(rig.delegate.iconShape == shape, "設完應更新 delegate.iconShape，應為 \(shape)")
                #expect(rig.spy.iconShapes.last == shape, """
                    .pickIconShape(\(shape)) 應該轉發到 status（spy.setIconShape），\
                    實際 \(String(describing: rig.spy.iconShapes.last))
                    """)
            }
        }
    }
}
