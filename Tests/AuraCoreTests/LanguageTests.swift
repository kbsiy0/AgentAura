import Testing
import AuraCore

/// D-1／D-2：`Language` 是顯示層參數的值域本身——只有兩個 case（D-6：不做第三語言的
/// 擴充機制，YAGNI，enum 加一個 case 就能長）。`rawValue` 供 `LanguagePreference`
/// （AgentAuraApp）落盤用，字面值釘死避免 `UserDefaults` 裡的舊字串因為改字面而讀不回來。
@Suite("Language：兩個 case，rawValue 釘死")
struct LanguageTests {

    @Test("恰好兩個 case：english／traditionalChinese")
    func exactlyTwoCases() {
        #expect(Language.allCases == [.english, .traditionalChinese], """
            Language.allCases 實際是 \(Language.allCases)——這份測試釘住 D-6「先不做第三語言」，
            真的要加第三語言時這裡會提醒你同時檢查所有窮盡 switch（含 L10n* 字串表）
            """)
    }

    @Test("rawValue 釘死，UserDefaults 已落盤的舊字串不會因為改字面而讀不回來")
    func rawValuesArePinned() {
        #expect(Language.english.rawValue == "english")
        #expect(Language.traditionalChinese.rawValue == "traditionalChinese")
        #expect(Language(rawValue: "english") == .english)
        #expect(Language(rawValue: "traditionalChinese") == .traditionalChinese)
    }

    @Test("無法辨識的字串回 nil（LanguagePreference 靠這個 fallback 回預設值）")
    func unrecognizedRawValueIsNil() {
        #expect(Language(rawValue: "français") == nil)
        #expect(Language(rawValue: "") == nil)
    }
}
