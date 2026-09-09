import Testing
import AuraCore

/// spec `2026-09-09-m4-icon-form-design.md` §6：`animationCurveBoundaries`。
@Suite("AnimationCurve")
struct AnimationCurveTests {

    @Test("phase 0/0.5/1 的 alpha；double blink 四窗口 0.14/0.28/0.42 兩側；breathe 對稱")
    func animationCurveBoundaries() {
        let breathe = IconAnimation.breathe(period: 4.0, min: 0.2, max: 0.8)
        #expect(AnimationCurve.alpha(for: breathe, phase: 0) == 0.2, "phase 0 應為 lo(0.2)")
        #expect(AnimationCurve.alpha(for: breathe, phase: 0.5) == 0.8, "phase 0.5（中點）應為 hi(0.8)")
        #expect(AnimationCurve.alpha(for: breathe, phase: 1) == 0.2, "phase 1 應對稱回到 lo(0.2)")

        let blink = IconAnimation.doubleBlink(period: 1.1)
        let hi = 1.0
        let lo = 0.08
        #expect(AnimationCurve.alpha(for: blink, phase: 0.13) == hi, "第一次亮：0.14 前應為 hi")
        #expect(AnimationCurve.alpha(for: blink, phase: 0.14) == lo, "0.14 起應轉暗")
        #expect(AnimationCurve.alpha(for: blink, phase: 0.27) == lo, "0.28 前仍應暗")
        #expect(AnimationCurve.alpha(for: blink, phase: 0.28) == hi, "第二次亮：0.28 起應為 hi")
        #expect(AnimationCurve.alpha(for: blink, phase: 0.41) == hi, "0.42 前仍應亮")
        #expect(AnimationCurve.alpha(for: blink, phase: 0.42) == lo, "0.42 起應轉暗、留白到週期結束")
    }

    /// review-t01-0203 I1：`period(of:)` 原本零 gate——兩個 case 都改回 nil，全套件 251 測試零反應，
    /// 而 `AnimationDriver.reschedule()` 是 `period ?? 1.0`：working 4.0s／waiting 1.1s 全變 1.0s，
    /// R4「常態最安靜」靜默失效。既有 R4 suite 釘的是 policy 產出的 payload，不是「取出 period」這個動作。
    @Test("period(of:)：breathe／doubleBlink 回自己的週期，none 回 nil")
    func periodIsExtracted() {
        #expect(AnimationCurve.period(of: .breathe(period: 4.0, min: 0.35, max: 0.6)) == 4.0)
        #expect(AnimationCurve.period(of: .doubleBlink(period: 1.1)) == 1.1)
        #expect(AnimationCurve.period(of: .none) == nil, "靜態動畫沒有週期，driver 據此不排程")
    }
}
