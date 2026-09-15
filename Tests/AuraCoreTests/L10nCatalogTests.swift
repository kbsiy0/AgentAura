import Testing
import AuraCore

/// D-1 字串表機制的內容測試（機制本身——「少翻一個字串＝編譯錯誤」——由編譯器保證，
/// 不需要 runtime 測；這裡測的是**內容**：每個 key 兩種語言都答得出來、答案不同、
/// 帶參數的字串用插值而非 `String(format:)` 位置參數）。
@Suite("L10n 字串表：T26 示範用的 3 個鍵")
struct L10nCatalogTests {

    // MARK: - 純靜態字串（PanelModel.emptyRowsMessage 搬遷過來的）

    @Test("L10nPanel.emptyRowsMessage 兩種語言都非空，且不同")
    func emptyRowsMessageBothLanguages() {
        let en = L10nPanel.emptyRowsMessage.text(.english)
        let zh = L10nPanel.emptyRowsMessage.text(.traditionalChinese)
        #expect(!en.isEmpty && !zh.isEmpty)
        #expect(en != zh)
        #expect(zh == "Claude Code 開起來、開始跑之後，這裡會列出每個 session。", "搬遷後中文字面不得變（D-4：對齊不弱化）")
    }

    // MARK: - Options 列標題（純靜態）

    @Test("L10nOptionsMenu.languageRowTitle 兩種語言都非空，且不同")
    func languageRowTitleBothLanguages() {
        #expect(L10nOptionsMenu.languageRowTitle.text(.english) == "Language")
        #expect(L10nOptionsMenu.languageRowTitle.text(.traditionalChinese) == "顯示語言")
    }

    // MARK: - 帶參數字串（目標語言的自稱插值進句子，語序由各語言分支自己決定）

    @Test("languageDisplayName 窮盡兩個語言，各自回自己的自稱（endonym）")
    func languageDisplayNameIsEndonym() {
        #expect(L10nOptionsMenu.languageDisplayName(.english) == "English")
        #expect(L10nOptionsMenu.languageDisplayName(.traditionalChinese) == "繁體中文")
    }

    @Test("languageRowSubtitle 插值目標語言名稱，句子在顯示語言下組成——不是共用位置樣板")
    func languageRowSubtitleInterpolatesTarget() {
        let enSubtitle = L10nOptionsMenu.languageRowSubtitle(switchingTo: .traditionalChinese, displayLanguage: .english)
        let zhSubtitle = L10nOptionsMenu.languageRowSubtitle(switchingTo: .english, displayLanguage: .traditionalChinese)
        #expect(enSubtitle == "Switch to 繁體中文", "實際：\(enSubtitle)")
        #expect(zhSubtitle == "切換成English", "實際：\(zhSubtitle)")
        // 正向對照：換一個目標語言，插值內容真的跟著換（不是寫死的字面）。
        #expect(L10nOptionsMenu.languageRowSubtitle(switchingTo: .english, displayLanguage: .english) == "Switch to English")
        #expect(L10nOptionsMenu.languageRowSubtitle(switchingTo: .traditionalChinese, displayLanguage: .traditionalChinese)
                == "切換成繁體中文")
    }

    // MARK: - Registry：D-5(2)(3) 兩條 gate 的推導依據

    @Test("L10nRegistry.allEntries 非空、且涵蓋這 3 個示範鍵")
    func registryCoversDemoKeys() {
        let names = Set(L10nRegistry.allEntries.map(\.0))
        #expect(names.contains("L10nOptionsMenu.languageRowTitle"), "實際：\(names)")
        #expect(names.contains("L10nPanel.emptyRowsMessage"), "實際：\(names)")
    }

    @Test("registry 裡每個 entry 都窮盡 Language.allCases（沒有漏語言）")
    func registryEntriesCoverEveryLanguage() {
        #expect(!L10nRegistry.allEntries.isEmpty, "registry 是空的 —— gate 不能空跑")
        for (name, byLanguage) in L10nRegistry.allEntries {
            #expect(Set(byLanguage.keys) == Set(Language.allCases), "\(name) 缺語言：實際 \(byLanguage.keys)")
        }
    }
}
