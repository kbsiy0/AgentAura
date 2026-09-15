import Testing
import Foundation
import AuraCore

/// T13（S1-2 收尾）：persona 實測 Options 第一列承諾「說明與快速上手…」，但 `help.html`
/// 對「快速上手」「減少動態」「回報問題」「關於」「⌘Q」等關鍵詞完全 0 命中——B 波新增的
/// 五個表面裡唯一意思不自明的「減少動態」一個字都沒解釋。清單**不手抄**：直接從
/// `OptionsMenuModel.rows(...)` 的實際輸出推導核心關鍵詞，往後加一列忘了寫說明就會紅。
///
/// T30（i18n）：說明文件拆成 `help-<Language.rawValue>.html` 兩份——這裡改成對
/// `Language.allCases` 參數化（`@Test(arguments:)`），兩個語言版本**各自**守自己的檔，
/// 不是手寫「檢查 help.html 跟 help-english.html」這種會 drift 的清單；哪天 `Language`
/// 真的加第三個 case，這份 gate 自動多驗一個檔，不必改測試碼。
@Suite("help 文件涵蓋 Options 每一列在做什麼（T13 S1-2 起、T30 雙語化）")
struct HelpDocOptionsRowCoverageTests {

    /// 一個能踩到「全部列都出現」的代表狀態（`launchAtLogin` 非 nil、`recheckHook` 的
    /// `connected(_, .unknown)` 前提、非預設色盤讓 `resetColors` 不被跳過）——與
    /// `OptionsMenuModelTests.everyGroupIsReachable` 同樣的手法，不必窮盡全部組合，
    /// 這裡只需要「至少一次看到每一列」。
    static func allRows(language: Language) -> [OptionsRow] {
        OptionsMenuModel.rows(install: .connected(owner: .thisApp, verified: .unknown),
                              launchAtLogin: true, isDefaultPalette: false,
                              systemReduceMotion: false, userReduceMotion: false,
                              iconPlate: true, palette: .default, language: language)
    }

    /// 去掉純裝飾性的尾綴（「…」／「 ⌘Q」）——help 文件不必逐字複製選單列的標點符號，
    /// 但核心詞必須出現。兩個語言的標點尾綴形狀相同（`L10nOptionsMenuRows` 兩個分支都用
    /// 同一組「…」／「 ⌘Q」），共用同一個 trim 邏輯不必語言各寫一份。
    static func coreKeyword(_ title: String) -> String {
        var t = title
        if t.hasSuffix(" ⌘Q") { t.removeLast(3) }
        if t.hasSuffix("…") { t.removeLast() }
        return t
    }

    static func missingKeywords(in text: String, language: Language) -> [String] {
        Self.allRows(language: language).map { coreKeyword($0.title) }.filter { !text.contains($0) }
    }

    /// T30：檔名規則跟生產碼同一條（`AppDelegate.helpResourceName(for:)`，
    /// AuraCore 這一側看不到 AgentAuraApp target，所以在這裡重複同一個字面公式——
    /// 兩邊各自從 `Language.rawValue` 推導，不是互相參照的手抄清單）。
    static func helpFileName(for language: Language) -> String {
        "help-\(language.rawValue).html"
    }

    static func helpText(for language: Language) throws -> String {
        try String(contentsOf: Gate.repoRoot().appendingPathComponent("Resources/\(helpFileName(for: language))"),
                    encoding: .utf8)
    }

    @Test("定義域非空（gate 不能空跑）", arguments: Language.allCases)
    func rowsIsNotEmpty(language: Language) {
        #expect(Self.allRows(language: language).count >= OptionsRowGroup.allCases.count, """
            \(language) 代表狀態只踩到 \(Self.allRows(language: language).count) 列，
            比 group 數量還少 —— 可能選錯了代表狀態
            """)
    }

    @Test("help 文件含有每一列的核心關鍵詞（兩個語言版本各自守自己的檔）", arguments: Language.allCases)
    func helpDocCoversEveryRow(language: Language) throws {
        let missing = Self.missingKeywords(in: try Self.helpText(for: language), language: language)
        #expect(missing.isEmpty, """
            \(Self.helpFileName(for: language)) 沒有提到：\(missing.joined(separator: "、"))——
            Options 第一列承諾「說明與快速上手」，這裡卻沒解釋這些列在做什麼
            """)
    }

    /// 正向對照：確認 `missingKeywords` 真的抓得到遺漏，不是「怎麼測都是空陣列」的空氣測試。
    /// 拿掉的字面直接從 `L10nOptionsMenuRows.reduceMotion.text(language)` 取得（不手寫
    /// 中文或英文字面），兩個語言各自驗證同一件事。
    @Test("正向對照：拿掉一個關鍵詞的字面後，missingKeywords 真的抓得到", arguments: Language.allCases)
    func scanCatchesRealOmission(language: Language) throws {
        let text = try Self.helpText(for: language)
        let reduceMotionKeyword = L10nOptionsMenuRows.reduceMotion.text(language)
        let withoutReduceMotion = text.replacingOccurrences(of: reduceMotionKeyword, with: "")
        let missing = Self.missingKeywords(in: withoutReduceMotion, language: language)
        #expect(missing.contains(reduceMotionKeyword), """
            拿掉「\(reduceMotionKeyword)」字面之後，\(Self.helpFileName(for: language)) 的
            missingKeywords 應該抓到它，實際 \(missing)
            """)
    }
}
