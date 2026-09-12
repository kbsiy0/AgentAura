import Testing
import AuraCore

/// C2（team-lead 收尾）：`OptionsPanelSizing.heightCeiling(forRowCount:)` 純函式本身——
/// wired 端（真的用它擋 `preferredContentSize.height`）由 `OptionsExpandTests` 守。
@Suite("OptionsPanelSizing：高度門檻由列數推導")
struct OptionsPanelSizingTests {

    @Test("列數增加，門檻單調上升（加一列是合理成長，不必回頭改測試）")
    func ceilingGrowsMonotonicallyWithRowCount() {
        let c8 = OptionsPanelSizing.heightCeiling(forRowCount: 8)
        let c9 = OptionsPanelSizing.heightCeiling(forRowCount: 9)
        let c10 = OptionsPanelSizing.heightCeiling(forRowCount: 10)
        #expect(c9 > c8, "9 列的門檻應該比 8 列高")
        #expect(c10 > c9, "10 列的門檻應該比 9 列高")
        #expect(c9 - c8 == c10 - c9, "每多一列漲的幅度應該固定（線性推導，不是隨便加的常數）")
    }

    @Test("公式對實測 worst-case（10 列，411pt）留有正的安全邊際")
    func ceilingHasPositiveMarginOverMeasuredWorstCase() {
        let ceiling = OptionsPanelSizing.heightCeiling(forRowCount: 10)
        #expect(ceiling > 411, "10 列實測 411pt——門檻必須留邊際，不是卡在實測值上")
        #expect(ceiling - 411 < 200, "邊際也不能大到形同虛設（900pt 那種）——上限抓一個合理範圍")
    }

    @Test("rowCount 為 0（理論邊界）：門檻仍是正數，不會出現負的或 0 的荒謬值")
    func zeroRowCountStillPositive() {
        #expect(OptionsPanelSizing.heightCeiling(forRowCount: 0) > 0)
    }
}
