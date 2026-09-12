import Testing
import Foundation
import AuraCore

/// T13（S1-2 收尾）：persona 實測 Options 第一列承諾「說明與快速上手…」，但 `help.html`
/// 對「快速上手」「減少動態」「回報問題」「關於」「⌘Q」等關鍵詞完全 0 命中——B 波新增的
/// 五個表面裡唯一意思不自明的「減少動態」一個字都沒解釋。清單**不手抄**：直接從
/// `OptionsMenuModel.rows(...)` 的實際輸出推導核心關鍵詞，往後加一列忘了寫說明就會紅。
@Suite("help.html 涵蓋 Options 每一列在做什麼（T13，S1-2）")
struct HelpDocOptionsRowCoverageTests {

    /// 一個能踩到「全部列都出現」的代表狀態（`launchAtLogin` 非 nil、`recheckHook` 的
    /// `connected(_, .unknown)` 前提、非預設色盤讓 `resetColors` 不被跳過）——與
    /// `OptionsMenuModelTests.everyGroupIsReachable` 同樣的手法，不必窮盡全部組合，
    /// 這裡只需要「至少一次看到每一列」。
    static func allRows() -> [OptionsRow] {
        OptionsMenuModel.rows(install: .connected(owner: .thisApp, verified: .unknown),
                              launchAtLogin: true, isDefaultPalette: false,
                              systemReduceMotion: false, userReduceMotion: false,
                              iconPlate: true, palette: .default)
    }

    /// 去掉純裝飾性的尾綴（「…」／「 ⌘Q」）——help.html 不必逐字複製選單列的標點符號，
    /// 但核心詞必須出現。
    static func coreKeyword(_ title: String) -> String {
        var t = title
        if t.hasSuffix(" ⌘Q") { t.removeLast(3) }
        if t.hasSuffix("…") { t.removeLast() }
        return t
    }

    static func missingKeywords(in text: String) -> [String] {
        Self.allRows().map { coreKeyword($0.title) }.filter { !text.contains($0) }
    }

    static func helpText() throws -> String {
        try String(contentsOf: Gate.repoRoot().appendingPathComponent("Resources/help.html"), encoding: .utf8)
    }

    @Test("定義域非空（gate 不能空跑）")
    func rowsIsNotEmpty() {
        #expect(Self.allRows().count >= OptionsRowGroup.allCases.count, """
            代表狀態只踩到 \(Self.allRows().count) 列，比 group 數量還少 —— 可能選錯了代表狀態
            """)
    }

    @Test("help.html 含有每一列的核心關鍵詞")
    func helpDocCoversEveryRow() throws {
        let missing = Self.missingKeywords(in: try Self.helpText())
        #expect(missing.isEmpty, """
            help.html 沒有提到：\(missing.joined(separator: "、"))——
            Options 第一列承諾「說明與快速上手」，這裡卻沒解釋這些列在做什麼
            """)
    }

    /// 正向對照：確認 `missingKeywords` 真的抓得到遺漏，不是「怎麼測都是空陣列」的空氣測試。
    @Test("正向對照：拿掉一個關鍵詞的字面後，missingKeywords 真的抓得到")
    func scanCatchesRealOmission() throws {
        let text = try Self.helpText()
        let withoutReduceMotion = text.replacingOccurrences(of: "減少動態", with: "")
        let missing = Self.missingKeywords(in: withoutReduceMotion)
        #expect(missing.contains("減少動態"), "拿掉「減少動態」字面之後，missingKeywords 應該抓到它，實際 \(missing)")
    }
}
