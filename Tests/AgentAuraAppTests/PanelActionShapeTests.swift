import Testing
import AuraCore

/// `samples(_:)` 的 round-trip 對每個 `PanelActionKind` 都成立，且
/// `PanelActionKind.allCases.flatMap(PanelAction.samples)` 的數量由型別推導、不寫死。
/// T04 落地前，本檔 `import AuraCore` 撞名到 `Tests/AgentAuraAppTests/Support/PendingActionTypes.swift`
/// 的同名 T01 stub（同 target 內、無 `public` 的型別遮蔽掉 import 進來的），驗的是 stub 內部一致；
/// T04 把 stub 刪掉、`PanelAction`／`PanelActionKind` 落地在 `Sources/AuraCore/PanelAction.swift` 之後，
/// 這條測試原封不動地變成正式的 round-trip 守門——這正是它從綠保持綠的理由。
@Suite("PanelAction stub 的 samples／kind round-trip")
struct PanelActionShapeTests {

    @Test("每個 Kind 的 samples(_:) 都非空，且每個 PanelAction 的 kind 都指回同一個 Kind")
    func samplesRoundTripToTheirOwnKind() {
        for kind in PanelActionKind.allCases {
            let samples = PanelAction.samples(kind)
            #expect(!samples.isEmpty, ".\(kind) 的 samples(_:) 不得為空——單一代表值會讓部分變體綠得不合理（N7）")
            #expect(samples.allSatisfy { $0.kind == kind }, ".\(kind) 的某個 sample 的 kind 指回了別的 Kind")
        }
    }

    @Test("setLaunchAtLogin 的 samples 同時含 true／false（N7 明確要求的那個反例）")
    func setLaunchAtLoginCoversBothBooleans() {
        let samples = PanelAction.samples(.setLaunchAtLogin)
        #expect(samples.contains(.setLaunchAtLogin(true)))
        #expect(samples.contains(.setLaunchAtLogin(false)))
    }

    @Test("pickColor 的 samples 覆蓋 Activity.customizable 全部四個值")
    func pickColorCoversAllCustomizableActivities() {
        let samples = PanelAction.samples(.pickColor)
        let activities = samples.compactMap { action -> Activity? in
            if case let .pickColor(a) = action { return a }
            return nil
        }
        #expect(Set(activities) == Set(Activity.customizable), "pickColor 應覆蓋 Activity.customizable 全部四個值")
    }
}
