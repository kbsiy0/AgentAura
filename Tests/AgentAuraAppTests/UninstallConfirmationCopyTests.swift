import Testing
import Foundation
@testable import AgentAuraApp
import AuraCore

/// T24（team-lead 文案審查）：使用者原話「對話框裡寫的東西太文謅謅了，稍微排版一下吧，
/// 條列式一點，使用者大部分都不是工程師，不用寫太技術」。這裡驗**語意標記**（每件事的
/// 使用者感受得到的後果都要被提到、技術字面不得出現），不是死板的整段字串相等——
/// 那種斷言只要換個標點就要重寫，也驗不出「到底有沒有講人話」。
///
/// T29（i18n）：`UninstallConfirmation.title`／`.body` 從 `static let` 改成吃 `language:`
/// 的函式——中文那組斷言明確傳 `.traditionalChinese`（D-4：對齊新契約，內容不變），
/// 英文那組是新增的一半（team-lead 要求「英文那半也要有等價的語意 gate，不要只守中文」），
/// 兩組各自的關鍵詞、句長判準都是**該語言自己的單位**：中文用「字元數」（CJK 一字約一個
/// 語意單位），英文用「單字數」（英文一個單字才對應中文一個字的資訊量，字元數在英文裡
/// 不是恰當的短句判準）。
@MainActor
@Suite("UninstallConfirmation 文案（T24 用字審查，T29 加英文對照）")
struct UninstallConfirmationCopyTests {

    // MARK: - 中文（原有斷言，內容不變，只補 language 參數）

    /// 每件事的「使用者感受得到的後果」關鍵詞——不是逐字複製 body，是這句話該講的概念。
    static let requiredConcepts = ["開機自動啟動", "選單列", "顏色", "垃圾桶", "救回來"]

    /// 技術字面：對非工程師沒有意義，且是使用者原話要求拿掉的那種東西。
    static let bannedLiterals = ["~/.claude", "symlink", "persistent domain", "defaults",
                                 ".agentaura", "NSApp", "UserDefaults"]

    @Test("body 提到每一個使用者感受得到的後果")
    func bodyCoversEveryUserFacingConsequence() {
        let body = UninstallConfirmation.body(.traditionalChinese)
        let missing = Self.requiredConcepts.filter { !body.contains($0) }
        #expect(missing.isEmpty, "UninstallConfirmation.body 沒提到：\(missing.joined(separator: "、"))")
    }

    @Test("body 不含任何技術字面")
    func bodyContainsNoTechnicalLiterals() {
        let body = UninstallConfirmation.body(.traditionalChinese)
        let present = Self.bannedLiterals.filter { body.contains($0) }
        #expect(present.isEmpty, "UninstallConfirmation.body 仍含技術字面：\(present.joined(separator: "、"))——使用者要求別寫這些")
    }

    @Test("body 是條列式——至少有 requiredConcepts 數量的項目符號行")
    func bodyIsBulleted() {
        let bulletLines = UninstallConfirmation.body(.traditionalChinese).split(separator: "\n").filter { $0.contains("•") }
        #expect(bulletLines.count >= Self.requiredConcepts.count, """
            項目符號行只有 \(bulletLines.count) 行，少於要求覆蓋的 \(Self.requiredConcepts.count) 個後果——
            文案應該逐項條列，不是擠成一段話
            """)
    }

    /// 「短句」用可量測的方式定義：每個項目符號行（含符號本身）不超過 20 個字元。
    @Test("每個項目符號行都是短句（≤20 字元，不含前導空白／符號）")
    func bulletLinesAreShort() {
        let bulletLines = UninstallConfirmation.body(.traditionalChinese).split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("•") }
        for line in bulletLines {
            let content = line.dropFirst().trimmingCharacters(in: .whitespaces)
            #expect(content.count <= 20, "「\(content)」有 \(content.count) 字元，超過 20 字元的短句上限")
        }
    }

    @Test("title 沒有變得更技術——仍是使用者已經看過的措辭")
    func titleUnchanged() {
        #expect(UninstallConfirmation.title(.traditionalChinese) == "完整移除 AgentAura？")
    }

    /// 正向對照：確認 `requiredConcepts` 檢查真的抓得到遺漏，不是空氣測試
    /// （同 `HelpDocOptionsRowCoverageTests.scanCatchesRealOmission` 的手法）。
    @Test("正向對照：拿掉一個概念關鍵詞後，覆蓋檢查真的抓得到")
    func coverageCheckCatchesRealOmission() {
        let withoutTrash = UninstallConfirmation.body(.traditionalChinese).replacingOccurrences(of: "垃圾桶", with: "")
        let missing = Self.requiredConcepts.filter { !withoutTrash.contains($0) }
        #expect(missing.contains("垃圾桶"), "拿掉「垃圾桶」字面之後，覆蓋檢查應該抓到它，實際 \(missing)")
    }

    /// 正向對照：確認技術字面檢查真的抓得到違規。
    @Test("正向對照：混進一個技術字面後，禁字檢查真的抓得到")
    func bannedLiteralCheckCatchesRealViolation() {
        let withLeak = UninstallConfirmation.body(.traditionalChinese) + "\n~/.claude 也會被動到"
        let present = Self.bannedLiterals.filter { withLeak.contains($0) }
        #expect(present.contains("~/.claude"), "混進 ~/.claude 字面之後，禁字檢查應該抓到它")
    }

    /// T25（真機事故）：垃圾桶動作在無法解釋的情況下沒有真的落地，而對話框原文
    /// 「移到垃圾桶後，清空垃圾桶之前都可以救回來」是無條件保證——對那次的使用者是假話。
    /// 這個保證做出的時間點在動作**之前**（對話框是事前顯示），沒辦法等 recycle 真的
    /// 回報成功才講這句話，所以選擇把文案改成不做絕對承諾，而不是把承諾綁在事實上。
    @Test("結尾不做無條件保證——垃圾桶救援的說法要有保留，不是「一定」")
    func recoveryClaimIsHedgedNotAbsolute() {
        let body = UninstallConfirmation.body(.traditionalChinese)
        #expect(!body.contains("都可以救回來"), """
            「都可以救回來」是無條件保證——recycle 失敗時對使用者是假話（T25 實機事故）。
            文案應該用保留字眼淡化保證的絕對性，不承諾一定救得回來
            """)
        #expect(body.contains("通常"), "應該用「通常」之類的保留字眼淡化保證的絕對性")
    }

    // MARK: - 英文（T29 新增，與中文那組同語意、不同單位）

    /// 中文版用「概念」比對（`.contains(概念)`），英文版一樣用概念詞，但挑英文讀者
    /// 會辨識的字眼，不是逐詞翻譯中文關鍵詞。
    static let requiredConceptsEnglish = ["login", "menu bar", "colors", "Trash", "recover"]

    /// 大小寫不敏感——「Menu bar stops showing status」這種句首大寫，跟關鍵詞
    /// 「menu bar」對讀者是同一件事，不該因為大小寫沒對齊就判定漏講（同下面
    /// `englishRecoveryClaimIsHedgedNotAbsolute` 對 "usually" 的既有處理方式）。
    @Test("英文 body 提到每一個使用者感受得到的後果")
    func englishBodyCoversEveryUserFacingConsequence() {
        let body = UninstallConfirmation.body(.english).lowercased()
        let missing = Self.requiredConceptsEnglish.filter { !body.contains($0.lowercased()) }
        #expect(missing.isEmpty, "英文 body 沒提到：\(missing.joined(separator: ", "))")
    }

    @Test("英文 body 不含任何技術字面")
    func englishBodyContainsNoTechnicalLiterals() {
        let body = UninstallConfirmation.body(.english)
        let present = Self.bannedLiterals.filter { body.contains($0) }
        #expect(present.isEmpty, "英文 body 仍含技術字面：\(present.joined(separator: ", "))")
    }

    @Test("英文 body 是條列式——至少有 requiredConceptsEnglish 數量的項目符號行")
    func englishBodyIsBulleted() {
        let bulletLines = UninstallConfirmation.body(.english).split(separator: "\n").filter { $0.contains("•") }
        #expect(bulletLines.count >= Self.requiredConceptsEnglish.count, """
            項目符號行只有 \(bulletLines.count) 行，少於要求覆蓋的 \(Self.requiredConceptsEnglish.count) 個後果
            """)
    }

    /// 英文「短句」的單位是**單字數**，不是字元數——英文一個單字才大略對應中文一個字的
    /// 資訊量，沿用中文版的字元上限（20）套在英文只會允許遠比中文冗長的句子。
    @Test("每個英文項目符號行都是短句（≤6 個單字，不含符號）")
    func englishBulletLinesAreShort() {
        let bulletLines = UninstallConfirmation.body(.english).split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("•") }
        #expect(!bulletLines.isEmpty, "英文 body 找不到任何項目符號行")
        for line in bulletLines {
            let content = line.dropFirst().trimmingCharacters(in: .whitespaces)
            let wordCount = content.split(separator: " ").count
            #expect(wordCount <= 6, "「\(content)」有 \(wordCount) 個單字，超過 6 個單字的短句上限")
        }
    }

    @Test("英文 title 是使用者已看過中文措辭的對應英譯")
    func englishTitleMatches() {
        #expect(UninstallConfirmation.title(.english) == "Completely remove AgentAura?")
    }

    /// 正向對照，同中文版 `coverageCheckCatchesRealOmission`。
    @Test("正向對照：英文拿掉一個概念關鍵詞後，覆蓋檢查真的抓得到")
    func englishCoverageCheckCatchesRealOmission() {
        let withoutTrash = UninstallConfirmation.body(.english).replacingOccurrences(of: "Trash", with: "")
        let missing = Self.requiredConceptsEnglish.filter { !withoutTrash.contains($0) }
        #expect(missing.contains("Trash"), "拿掉「Trash」字面之後，覆蓋檢查應該抓到它，實際 \(missing)")
    }

    /// 正向對照，同中文版 `bannedLiteralCheckCatchesRealViolation`。
    @Test("正向對照：英文混進一個技術字面後，禁字檢查真的抓得到")
    func englishBannedLiteralCheckCatchesRealViolation() {
        let withLeak = UninstallConfirmation.body(.english) + "\n~/.claude is affected too"
        let present = Self.bannedLiterals.filter { withLeak.contains($0) }
        #expect(present.contains("~/.claude"), "混進 ~/.claude 字面之後，禁字檢查應該抓到它")
    }

    /// 英文版同 T25 的教訓：結尾不做無條件保證。
    @Test("英文結尾不做無條件保證——用 hedge 字眼，不是「一定」")
    func englishRecoveryClaimIsHedgedNotAbsolute() {
        let body = UninstallConfirmation.body(.english)
        #expect(!body.contains("always recoverable"), """
            無條件保證在 recycle 失敗時對使用者是假話（同 T25 中文版的教訓）
            """)
        #expect(body.lowercased().contains("usually"), "應該用「usually」之類的保留字眼淡化保證的絕對性")
    }
}
