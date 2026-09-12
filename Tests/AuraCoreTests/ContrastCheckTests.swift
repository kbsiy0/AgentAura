import Testing
import AuraCore

/// T19 配套 C：`ContrastCheck.lowOnLightBar` 的純函式驗證（不碰渲染）。
/// 見 `Sources/AuraCore/ContrastCheck.swift` 的 doc comment——參照背景＝純白、門檻 < 1.5:1，
/// 這裡逐色驗證，不是抄 team-lead 給的那張（不同參照背景下的）對照表。
@Suite("ContrastCheck（T19）")
struct ContrastCheckTests {

    @Test("白色（新預設 working）在淺色選單列上幾乎看不見")
    func whiteIsLowOnLightBar() {
        #expect(ContrastCheck.lowOnLightBar(RGBA(r: 1, g: 1, b: 1, a: 1)) == true, """
            白色對純白參照背景的對比恆為 1:1——這是「看不見」最極端的例子，必須觸發
            """)
    }

    @Test("舊預設 systemBlue 在淺色選單列上不算低對比")
    func oldDefaultBlueIsNotLowOnLightBar() {
        let systemBlue = RGBA(r: 10.0 / 255, g: 132.0 / 255, b: 255.0 / 255, a: 1)
        #expect(ContrastCheck.lowOnLightBar(systemBlue) == false, """
            舊預設藍對純白的對比約 3.65:1，遠高於 1.5 門檻，不該被判定為低對比
            """)
    }

    /// 目前 `.default` 的四個可改色狀態各驗一次——`working`（新預設，白）之外三色都該過關，
    /// 這樣「底板關才提醒」才不會變成「逢底板關必提醒」（見 `OptionsMenuModelTests`
    /// 的 T19-c／T19-d：safePalette 四色過關時不該有 subtitle）。
    @Test("目前 .default 的 done／waiting／error 三色在淺色選單列上不算低對比；working（白）算")
    func currentDefaultColorsMatchExpectedVerdicts() {
        let expectations: [(Activity, Bool)] = [
            (.error, false), (.waiting, false), (.working, true), (.done, false),
        ]
        for (activity, expectedLow) in expectations {
            let color = IconPalette.default[activity]
            #expect(ContrastCheck.lowOnLightBar(color) == expectedLow, """
                .default 的 .\(activity)（\(color)）lowOnLightBar 應為 \(expectedLow)，
                實際 \(ContrastCheck.lowOnLightBar(color))
                """)
        }
    }

    /// 對抗式：門檻不是卡在 0 或 1 的退化值——中灰（介於白與四色之間）也該驗一次，
    /// 確認判準是真的算對比，不是「只認白色」的字面比對。
    @Test("中灰（對淺色選單列對比 ≈1.41:1）也判定為低對比（不是只認白色字面）")
    func midGrayCloseToWhiteIsAlsoLow() {
        // 0.85 灰對純白：((1+.05)/(linearize(0.85)+.05)) ≈ 1.05/0.740 ≈ 1.41—— 跟白色一樣該觸發。
        let midGray = RGBA(r: 0.85, g: 0.85, b: 0.85, a: 1)
        #expect(ContrastCheck.lowOnLightBar(midGray) == true, "0.85 中灰對淺色選單列應該也判定為低對比")
    }
}
