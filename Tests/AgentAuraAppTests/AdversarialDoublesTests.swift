import Testing
@testable import AgentAuraApp

/// T01 對抗式 double 的自我測試（`FakeLoginItem`／`FakeVerificationStore`／`FakeTerminator`）。
/// T07 之後 `LoginItem`／`HookVerificationStore` 已落地，`FakeLoginItem`／`FakeVerificationStore`
/// 直接對生產 protocol 實作（見兩檔的 T07 註記），這條測試原封不動地變成對生產型別
/// （`LoginItemError`／`AuraCore.Verification`）的驗證，理由同 `PanelActionShapeTests.swift`
/// 的先例（stub → 落地後測試不必改）。
@MainActor
@Suite("FakeLoginItem／FakeVerificationStore／FakeTerminator 自我驗證")
struct AdversarialDoublesTests {

    @Test("FakeLoginItem：isSupported=false 時 UI 該隱藏該列")
    func loginItemNotSupported() {
        let fake = FakeLoginItem(isSupported: false)
        #expect(fake.isSupported == false)
    }

    @Test("FakeLoginItem：set 需核准時 throw，且 isEnabled 與剛設定的值不一致（模擬系統沒真的打開）")
    func loginItemRequiresApprovalLeavesInconsistentState() {
        let fake = FakeLoginItem(initiallyEnabled: false, setBehavior: .requiresApprovalAndDoesNotActuallyEnable)
        #expect(throws: LoginItemError.requiresApproval) {
            try fake.set(true)
        }
        #expect(fake.isEnabled == false, "呼叫端請求 true，但 isEnabled 應仍是 false —— 開關必須彈回實際值")
        #expect(fake.setCallCount == 1)
    }

    @Test("FakeVerificationStore：三種行為各自回傳可區分的 Verification")
    func verificationStoreBehaviorsAreDistinguishable() {
        let matches = FakeVerificationStore(behavior: .matches)
        let mismatched = FakeVerificationStore(behavior: .mismatched)
        let unreadable = FakeVerificationStore(behavior: .unreadable)
        #expect(matches.verification(for: "1:1:1.0") == .verified)
        #expect(mismatched.verification(for: "1:1:1.0") != .verified)
        #expect(unreadable.verification(for: "1:1:1.0") != .verified)
        #expect(matches.verificationCallCount == 1)
        #expect(matches.requestedStamps == ["1:1:1.0"])
    }

    @Test("FakeTerminator：quit 呼叫次數被記錄，且型別上不可能碰到 NSApp")
    func terminatorRecordsCallsWithoutTouchingRealApp() {
        let fake = FakeTerminator()
        fake.terminate()
        fake.terminate()
        #expect(fake.terminateCallCount == 2)
    }
}
