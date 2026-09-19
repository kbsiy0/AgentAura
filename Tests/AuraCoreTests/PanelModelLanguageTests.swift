import Testing
import AuraCore

/// D-3：`PanelModel.make` 多吃一個 `language`，且**沒有預設值**（同 `install` 的理由，
/// `PanelModelMakeDefaultsTests` 那條既有 gate 會頂住——這裡只驗內容，不重驗機制）。
/// `emptyRowsMessage` 是 T26 示範的「純靜態、非 row 標題」demo，搬進 `L10nPanel` 後
/// 這裡驗證它真的跟著 `language` 換。
@Suite("PanelModel.language：D-3 顯示層參數往下傳")
struct PanelModelLanguageTests {

    static func model(language: Language) -> PanelModel {
        PanelModel.make(icon: .empty, sessions: [], palette: .default,
                        install: .connected(owner: .thisApp, verified: .verified), version: "1.0",
                        optionsExpanded: false, launchAtLogin: nil, externalTargetPath: nil, banner: nil,
                        systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip,
                        language: language, codex: .unavailable, codexSnippet: nil)
    }

    @Test("emptyRowsMessage 隨 language 換語言，內容與 L10nPanel 一致（同一個 oracle）")
    func emptyRowsMessageFollowsLanguage() {
        #expect(Self.model(language: .english).emptyRowsMessage == L10nPanel.emptyRowsMessage.text(.english))
        #expect(Self.model(language: .traditionalChinese).emptyRowsMessage
                == L10nPanel.emptyRowsMessage.text(.traditionalChinese))
        #expect(Self.model(language: .english).emptyRowsMessage != Self.model(language: .traditionalChinese).emptyRowsMessage)
    }

    @Test("language 欄位本身如實反映傳入值（顯示層參數，不是全域狀態——見 D-3）")
    func languageFieldReflectsInput() {
        #expect(Self.model(language: .english).language == .english)
        #expect(Self.model(language: .traditionalChinese).language == .traditionalChinese)
    }

    /// D-3 的可測性承諾：「同一份 model 兩種語言渲染」必須做得到——不靠任何全域開關，
    /// 兩次呼叫互不干擾（如果 language 是 `static var`，這條測試仍會綠得很可疑；
    /// 真正頂住 D-3 的是 `PanelModelMakeSignatureScan`／`IsolationTests` 這類結構性 gate，
    /// 這裡只是把「兩種語言可以同時存在」的承諾寫成看得懂的斷言）。
    @Test("同一次呼叫序列，兩種語言的 model 可以同時存在、互不覆蓋")
    func twoLanguageModelsCoexist() {
        let en = Self.model(language: .english)
        let zh = Self.model(language: .traditionalChinese)
        #expect(en.language == .english)
        #expect(zh.language == .traditionalChinese, "建立 en 之後不得反過來污染 zh")
    }
}
