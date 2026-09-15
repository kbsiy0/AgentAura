import Testing
import AuraCore

/// D-5(2)：每個字串表鍵的中英文字面不得相同，除非明列在
/// `L10nRegistry.allowedSameAcrossLanguages` 裡（產品名、`⌘Q` 這類）。
///
/// 比對邏輯抽成 `violatingKeys(in:allowed:)` 純函式（不依賴真的 registry 內容）——
/// 這樣正向／負向對照才能餵合成資料，不必真的在生產碼裡故意寫一個相同字面的鍵
/// 來自我命中（同 `L10nExhaustivenessSourceScanTests` 用字串拼接繞開自我命中的精神，
/// 這裡用「邏輯與資料分離」達到同樣效果）。
@Suite("D-5(2)：字串表中英文不得相同（允許清單需明列）")
struct L10nLanguagesDifferTests {

    /// 回傳「文字在允許語言數量下沒有湊齊那麼多種不同字面」的 key 名稱——
    /// 用「相異字面數」而非直接兩兩比較，日後語言數變動也不必重寫。
    static func violatingKeys(in entries: [(String, [Language: String])], allowed: Set<String>) -> [String] {
        entries
            .filter { !allowed.contains($0.0) }
            .filter { Set($0.1.values).count != Language.allCases.count }
            .map(\.0)
    }

    @Test("正向對照：兩語言字面相同、且不在允許清單裡——會被抓到")
    func flagsRealDuplicate() {
        let entries: [(String, [Language: String])] = [("Fake.dup", [.english: "同一句", .traditionalChinese: "同一句"])]
        #expect(Self.violatingKeys(in: entries, allowed: []) == ["Fake.dup"])
    }

    @Test("負對照：兩語言字面相同、但在允許清單裡——不會被抓到")
    func allowsListedException() {
        let entries: [(String, [Language: String])] = [("Fake.appName", [.english: "AgentAura", .traditionalChinese: "AgentAura"])]
        #expect(Self.violatingKeys(in: entries, allowed: ["Fake.appName"]).isEmpty)
    }

    @Test("負對照：兩語言字面不同——不會被抓到")
    func cleanEntryIsNotFlagged() {
        let entries: [(String, [Language: String])] = [("Fake.ok", [.english: "hello", .traditionalChinese: "哈囉"])]
        #expect(Self.violatingKeys(in: entries, allowed: []).isEmpty)
    }

    /// 真正的 gate：對 `L10nRegistry.allEntries` 跑同一個函式。
    @Test("L10nRegistry.allEntries 裡沒有未列名的中英文相同鍵")
    func registryHasNoUnlistedDuplicates() {
        #expect(!L10nRegistry.allEntries.isEmpty, "registry 是空的 —— gate 不能空跑")
        let violating = Self.violatingKeys(in: L10nRegistry.allEntries, allowed: L10nRegistry.allowedSameAcrossLanguages)
        #expect(violating.isEmpty, """
            以下鍵的中英文字面相同，卻不在 allowedSameAcrossLanguages 裡：\(violating.sorted())——
            多半是忘了翻；如果是刻意的（產品名／版本號／⌘Q），把鍵名加進
            L10nRegistry.allowedSameAcrossLanguages 並寫明理由
            """)
    }
}
