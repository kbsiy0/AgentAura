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

    /// **test-edit scrutiny（D-u／spec §4.9）**：原本輸入是 `gpt-4o`，逐字釘死
    /// `Jargon.model("gpt-4o") == "gpt-4o"`。D-u 之後 `gpt-4o` 進了 Codex 家族分支，
    /// 不再原樣回傳（見下面 `modelCodexGpt4o`），所以這條測試的**原意**——「兩個非
    /// 數字段 → 原樣回傳」（既有 Claude 家族演算法規則 6 的性質）——改用不屬於
    /// Codex 家族的例子 `foo-bar-5` 保住：`["foo","bar","5"]` 是兩個非數字段
    /// （`foo`／`bar`）＋一個數字段，形狀仍然成立，只是換了一個不會被 Codex 分支
    /// 攔截的輸入。測試名不變、被測性質不變，斷言數在本檔案是增加（另外新增
    /// `modelCodexGpt4o` 釘死 `gpt-4o` 的新期望值），不是刪掉這條。
    @Test("model：foo-bar-5 → foo-bar-5（兩個非數字段 → 原樣回傳；輸入換成非 Codex 家族範例）")
    func modelTwoNonNumericSegmentsPassesThrough() { #expect(Jargon.model("foo-bar-5") == "foo-bar-5") }

    @Test("model：claude → claude（無數字段 → 原樣回傳）")
    func modelNoNumericSegmentPassesThrough() { #expect(Jargon.model("claude") == "claude") }

    @Test("model：空字串 → 空字串")
    func modelEmptyString() { #expect(Jargon.model("") == "") }

    // ---- model：Codex 家族命名（D-u／spec §4.9，CX41 釘死表，九列） ----
    //
    // Codex 家族分支排在既有六條規則**之前**；既有六條規則一行不動，判不出來
    // 落回既有的「原樣回傳」。四步規則：① 先抓 `[...]` 尾綴（與既有規則 1 同形）
    // ② `o` + 數字開頭的第一段（`o3`／`o4`）→ 整串原樣回傳 ③ 否則前綴必須是
    // `gpt-`，去前綴後固定為 `GPT`，第一個剩餘段以連字號接上 ④ 之後每一段首字
    // 大寫、以空白連接。任一步不符 → 落回既有演算法（上面九列既有輸出完全不變）。

    @Test("model（Codex）：gpt-5.5 → GPT-5.5（唯一實測值，round4-codex.ndjson 的 model）")
    func modelCodexGpt55() { #expect(Jargon.model("gpt-5.5") == "GPT-5.5") }

    @Test("model（Codex）：gpt-5.5-codex → GPT-5.5 Codex")
    func modelCodexGpt55Codex() { #expect(Jargon.model("gpt-5.5-codex") == "GPT-5.5 Codex") }

    @Test("model（Codex）：gpt-4o → GPT-4o（test-edit scrutiny 的新期望值，見上方註解）")
    func modelCodexGpt4o() { #expect(Jargon.model("gpt-4o") == "GPT-4o") }

    /// **刻意變更（r4 M1）**：現行（Codex 分支落地前）`Jargon.model("gpt-5")` 回傳
    /// `Gpt 5`——`["gpt","5"]` 的 `5` 是純數字，既有演算法**成功**並回傳 `Gpt 5`，
    /// 不落回原樣回傳，所以既不在任何 fixture（層一看不到）也不在原本的九列釘死表
    /// （層二看不到），正好掉在兩層守衛之間。D-u 之後 Codex 分支排在既有演算法之前，
    /// 這個輸入變成 `GPT-5`——一個使用者看得到的字串靜默改變，必須釘住讓它成為
    /// 一個被記錄的決定，不是副作用。
    @Test("model（Codex）：gpt-5 → GPT-5（刻意變更，現行是 Gpt 5，見上方註解）")
    func modelCodexGpt5() { #expect(Jargon.model("gpt-5") == "GPT-5") }

    @Test("model（Codex）：gpt-4.1-mini → GPT-4.1 Mini（釘住規則③／④分工：第一段連字號、其餘空白＋首字大寫）")
    func modelCodexGpt41Mini() { #expect(Jargon.model("gpt-4.1-mini") == "GPT-4.1 Mini") }

    @Test("model（Codex）：gpt-5.5[high] → GPT-5.5 (HIGH)（釘住規則①：先處理 [...] 尾綴，與既有規則同形）")
    func modelCodexGpt55High() { #expect(Jargon.model("gpt-5.5[high]") == "GPT-5.5 (HIGH)") }

    @Test("model（Codex）：o3 → o3（o 系列維持小寫，不得改成 O3）")
    func modelCodexO3() { #expect(Jargon.model("o3") == "o3") }

    @Test("model（Codex）：o4-mini → o4-mini（o 系列整串原樣回傳）")
    func modelCodexO4Mini() { #expect(Jargon.model("o4-mini") == "o4-mini") }
}
