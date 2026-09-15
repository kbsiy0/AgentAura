/// D-1／D-3（i18n design）：顯示語言——面板文字的一個顯示層參數，不是全域狀態
/// （見 `PanelModel.make` 的 `language:` 參數，與 `L10n*.swift` 字串表）。
///
/// D-6：只做兩個 case，不做第三語言的擴充機制（YAGNI）——加一個 case 就能長，
/// 但那一動會讓所有 `L10n*.swift` 的窮盡 `switch` 一次全部編不過（這正是機制的地基，
/// 見 `L10nCatalog`）。`rawValue` 給 `LanguagePreference`（AgentAuraApp）落盤用，
/// 字面值釘死（`LanguageTests.rawValuesArePinned`）——已落盤的舊字串不因改字面而失效。
public enum Language: String, Sendable, Equatable, CaseIterable {
    case english
    case traditionalChinese
}
