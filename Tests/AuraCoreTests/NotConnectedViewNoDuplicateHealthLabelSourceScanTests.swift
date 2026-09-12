import Testing
import Foundation

/// T13（S1-1 收尾）：`NotConnectedView` 先前無條件印一次 `model.install.healthLabel`，
/// 跟頂端 `PanelView.title`（對這個 view 涵蓋的每一種狀態恆相等，見
/// `TooltipAndTitleConsistencyTests`）撞成同一句；連同 footer chip 是第三次
/// （persona r2 S1-1）。修法是這裡直接不再讀 `model.install.healthLabel`，
/// 改用 `model.notConnectedDetailText`。
///
/// `PanelBodyTitleChipDistinctTests` 在 model 層驗證 `notConnectedDetailText` 本身
/// 不會跟 `title` 撞字，但那是「這個屬性的值對不對」，抓不到「view 是不是還多畫了一次
/// healthLabel」——這兩件事是獨立的（view 可以兩個都畫，個別屬性各自正確，但畫面上仍然
/// 三句話裡有兩句一樣）。這裡直接掃原始碼，防止有人把那一行原封不動貼回去。
@Suite("NotConnectedView 不得直接讀 install.healthLabel（T13，S1-1）")
struct NotConnectedViewNoDuplicateHealthLabelSourceScanTests {
    static func fileText() throws -> String {
        try String(contentsOf: Gate.repoRoot()
            .appendingPathComponent("Sources/AgentAuraApp/NotConnectedView.swift"), encoding: .utf8)
    }

    @Test("NotConnectedView.swift 不含 model.install.healthLabel 這個讀取")
    func doesNotReadHealthLabelDirectly() throws {
        let text = try Self.fileText()
        #expect(!text.contains("model.install.healthLabel"), """
            NotConnectedView.swift 又出現了 model.install.healthLabel —— 這會跟頂端
            PanelView.title 撞成同一句（S1-1），應該改讀 model.notConnectedDetailText
            """)
    }
}
