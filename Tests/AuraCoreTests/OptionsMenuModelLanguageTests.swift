import Testing
import AuraCore

/// T26（i18n）：「顯示語言」列——拆成獨立檔案，同 `AppDelegatePanelActionsWiredTests+T16.swift`
/// 那批的理由：`OptionsMenuModelTests.swift` 已經很接近 300 行的 Tests 上限。
@Suite("OptionsMenuModel.rows：顯示語言列（T26）")
struct OptionsMenuModelLanguageTests {

    private static func languageRow(_ language: Language) -> OptionsRow {
        let rows = OptionsMenuModel.rows(install: .notConnected, launchAtLogin: true, isDefaultPalette: true,
                                         systemReduceMotion: false, userReduceMotion: false,
                                         iconPlate: true, palette: .default, language: language)
        return rows.first { $0.action.kind == .setLanguage }!
    }

    /// 標題／副標讀字串表隨 language 換、action 雙向切成另一語言、非 toggle（語言不是二元
    /// 開/關語意）。
    @Test("內容隨 language 換，action 雙向切成另一語言，非 toggle 型")
    func contentAndCyclingBothDirections() {
        let en = Self.languageRow(.english), zh = Self.languageRow(.traditionalChinese)
        #expect(en.title == L10nOptionsMenu.languageRowTitle.text(.english))
        #expect(zh.title == L10nOptionsMenu.languageRowTitle.text(.traditionalChinese))
        #expect(en.action == .setLanguage(.traditionalChinese), "英文畫面應切成中文")
        #expect(zh.action == .setLanguage(.english), "中文畫面應切成英文")
        #expect(en.group == .settings && en.toggleValue == nil)
    }

    /// 恆在，不因 install 狀態隱藏——同 `resetColors`／`setIconPlate` 那批列。
    @Test("語言列跨所有 InstallState 恆在")
    func alwaysPresentAcrossInstallStates() {
        for install in InstallStateAllCases.all() {
            let rows = OptionsMenuModel.rows(install: install, launchAtLogin: nil, isDefaultPalette: true,
                                             systemReduceMotion: false, userReduceMotion: false, iconPlate: true, palette: .default, language: .traditionalChinese)
            #expect(rows.contains { $0.action.kind == .setLanguage }, "install=\(install) 缺語言列")
        }
    }
}
