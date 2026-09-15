import Testing
@testable import AuraCore

/// G9a（spec §3.4／§6.3）：迭代 `Jargon.effortMap`／`permissionModeMap` **本身**當來源集合——
/// 新增一個 key 就自動被這條蓋到，不必手動追加測試。`model` 是演算法不是查表，
/// 走 §3.4 的九列反例表。
///
/// T27（i18n）：兩個查表現在吃 `language`（預設中文，見 `Jargon.swift` 的 T27 註解），
/// D-4 對齊——原本斷言中文內容不變，只是明確指定 `.traditionalChinese`；另外補一組
/// `.english` 版本，兩個語言都要「查表結果一致、不回顯 key 本身」。
@Suite("Jargon：代碼字 → 人話")
struct JargonTests {

    @Test("effortMap 每個 key 查表結果一致、且輸出不等於 key 本身（不是沒翻譯）——兩種語言都要", arguments: Language.allCases)
    func effortMapNeverEchoesKey(_ language: Language) {
        let map = Jargon.effortMap(language)
        #expect(!map.isEmpty, "字典是空的 —— gate 不能空跑")
        for (key, value) in map {
            #expect(Jargon.effort(key, language: language) == value, "查表結果應等於字典值，實際：\(Jargon.effort(key, language: language))")
            #expect(value != key, "\(language) 下 key「\(key)」的人話輸出跟自己一樣，沒有真的翻譯")
        }
    }

    @Test("permissionModeMap 含 auto（實測 141 個 payload 裡最常見），且每個 key 都真的被翻譯——兩種語言都要", arguments: Language.allCases)
    func permissionModeMapNeverEchoesKeyAndHasAuto(_ language: Language) {
        let map = Jargon.permissionModeMap(language)
        #expect(!map.isEmpty, "字典是空的 —— gate 不能空跑")
        #expect(map["auto"] != nil, "auto 是實測最常見的值，兩種語言都必須有對應")
        for (key, value) in map {
            #expect(Jargon.permissionMode(key, language: language) == value, "查表結果應等於字典值，實際：\(Jargon.permissionMode(key, language: language))")
            #expect(value != key, "\(language) 下 key「\(key)」的人話輸出跟自己一樣，沒有真的翻譯")
        }
    }

    @Test("中文 auto 維持「自動判斷」（D-4：對齊新契約，內容不變）")
    func permissionModeMapAutoChineseUnchanged() {
        #expect(Jargon.permissionModeMap(.traditionalChinese)["auto"] == "自動判斷",
                "auto 的語意是自動決定要不要問，不是一律接受，刻意跟 brainstorm 的「自動接受」不同（S2-3）")
    }

    @Test("英文 auto 避免暗示「全部自動接受」（那是 bypassPermissions 的語意）")
    func permissionModeMapAutoEnglishAvoidsBypassConfusion() {
        let auto = Jargon.permissionModeMap(.english)["auto"]
        let bypass = Jargon.permissionModeMap(.english)["bypassPermissions"]
        #expect(auto != nil && bypass != nil)
        #expect(auto != bypass, "auto 與 bypassPermissions 的英文文案不得相同，語意不同（S2-3 的英文對應）")
    }

    @Test("未知值一律原樣回傳（payload 的欄位是自由字串，映射不得吃掉資訊）")
    func unknownValuesPassThrough() {
        #expect(Jargon.effort("ultra", language: .traditionalChinese) == "ultra")
        #expect(Jargon.permissionMode("yolo", language: .traditionalChinese) == "yolo")
        #expect(Jargon.model("") == "")
    }

    // ---- model：演算法，§3.4 九列反例表（與語言無關，`model` 不查字串表） ----

    @Test("model：claude-fable-5-1 → Fable 5.1")
    func modelFable() { #expect(Jargon.model("claude-fable-5-1") == "Fable 5.1") }

    @Test("model：claude-opus-5[1m] → Opus 5 (1M)（fixture 裡的真值）")
    func modelOpusWithBracketSuffix() { #expect(Jargon.model("claude-opus-5[1m]") == "Opus 5 (1M)") }

    @Test("model：claude-sonnet-5 → Sonnet 5")
    func modelSonnet() { #expect(Jargon.model("claude-sonnet-5") == "Sonnet 5") }

    @Test("model：claude-haiku-4-5-20251001 → Haiku 4.5（去日期段）")
    func modelHaikuWithDateSuffix() { #expect(Jargon.model("claude-haiku-4-5-20251001") == "Haiku 4.5") }

    @Test("model：claude-3-5-sonnet-20241022 → Sonnet 3.5（名字不在第一段也對）")
    func modelNameNotInFirstSegment() { #expect(Jargon.model("claude-3-5-sonnet-20241022") == "Sonnet 3.5") }

    @Test("model：opus-5 → Opus 5（無 claude- 前綴也接受）")
    func modelWithoutClaudePrefix() { #expect(Jargon.model("opus-5") == "Opus 5") }

    @Test("model：gpt-4o → gpt-4o（兩個非數字段 → 原樣回傳）")
    func modelTwoNonNumericSegmentsPassesThrough() { #expect(Jargon.model("gpt-4o") == "gpt-4o") }

    @Test("model：claude → claude（無數字段 → 原樣回傳）")
    func modelNoNumericSegmentPassesThrough() { #expect(Jargon.model("claude") == "claude") }

    @Test("model：空字串 → 空字串")
    func modelEmptyString() { #expect(Jargon.model("") == "") }
}
