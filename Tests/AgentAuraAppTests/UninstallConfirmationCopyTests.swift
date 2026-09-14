import Testing
import Foundation
@testable import AgentAuraApp

/// T24（team-lead 文案審查）：使用者原話「對話框裡寫的東西太文謅謅了，稍微排版一下吧，
/// 條列式一點，使用者大部分都不是工程師，不用寫太技術」。這裡驗**語意標記**（每件事的
/// 使用者感受得到的後果都要被提到、技術字面不得出現），不是死板的整段字串相等——
/// 那種斷言只要換個標點就要重寫，也驗不出「到底有沒有講人話」。
@MainActor
@Suite("UninstallConfirmation 文案（T24 用字審查）")
struct UninstallConfirmationCopyTests {

    /// 每件事的「使用者感受得到的後果」關鍵詞——不是逐字複製 body，是這句話該講的概念。
    static let requiredConcepts = ["開機自動啟動", "選單列", "顏色", "垃圾桶", "救回來"]

    /// 技術字面：對非工程師沒有意義，且是使用者原話要求拿掉的那種東西。
    static let bannedLiterals = ["~/.claude", "symlink", "persistent domain", "defaults",
                                 ".agentaura", "NSApp", "UserDefaults"]

    @Test("body 提到每一個使用者感受得到的後果")
    func bodyCoversEveryUserFacingConsequence() {
        let missing = Self.requiredConcepts.filter { !UninstallConfirmation.body.contains($0) }
        #expect(missing.isEmpty, "UninstallConfirmation.body 沒提到：\(missing.joined(separator: "、"))")
    }

    @Test("body 不含任何技術字面")
    func bodyContainsNoTechnicalLiterals() {
        let present = Self.bannedLiterals.filter { UninstallConfirmation.body.contains($0) }
        #expect(present.isEmpty, "UninstallConfirmation.body 仍含技術字面：\(present.joined(separator: "、"))——使用者要求別寫這些")
    }

    @Test("body 是條列式——至少有 requiredConcepts 數量的項目符號行")
    func bodyIsBulleted() {
        let bulletLines = UninstallConfirmation.body.split(separator: "\n").filter { $0.contains("•") }
        #expect(bulletLines.count >= Self.requiredConcepts.count, """
            項目符號行只有 \(bulletLines.count) 行，少於要求覆蓋的 \(Self.requiredConcepts.count) 個後果——
            文案應該逐項條列，不是擠成一段話
            """)
    }

    /// 「短句」用可量測的方式定義：每個項目符號行（含符號本身）不超過 20 個字元。
    @Test("每個項目符號行都是短句（≤20 字元，不含前導空白／符號）")
    func bulletLinesAreShort() {
        let bulletLines = UninstallConfirmation.body.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("•") }
        for line in bulletLines {
            let content = line.dropFirst().trimmingCharacters(in: .whitespaces)
            #expect(content.count <= 20, "「\(content)」有 \(content.count) 字元，超過 20 字元的短句上限")
        }
    }

    @Test("title 沒有變得更技術——仍是使用者已經看過的措辭")
    func titleUnchanged() {
        #expect(UninstallConfirmation.title == "完整移除 AgentAura？")
    }

    /// 正向對照：確認 `requiredConcepts` 檢查真的抓得到遺漏，不是空氣測試
    /// （同 `HelpDocOptionsRowCoverageTests.scanCatchesRealOmission` 的手法）。
    @Test("正向對照：拿掉一個概念關鍵詞後，覆蓋檢查真的抓得到")
    func coverageCheckCatchesRealOmission() {
        let withoutTrash = UninstallConfirmation.body.replacingOccurrences(of: "垃圾桶", with: "")
        let missing = Self.requiredConcepts.filter { !withoutTrash.contains($0) }
        #expect(missing.contains("垃圾桶"), "拿掉「垃圾桶」字面之後，覆蓋檢查應該抓到它，實際 \(missing)")
    }

    /// 正向對照：確認技術字面檢查真的抓得到違規。
    @Test("正向對照：混進一個技術字面後，禁字檢查真的抓得到")
    func bannedLiteralCheckCatchesRealViolation() {
        let withLeak = UninstallConfirmation.body + "\n~/.claude 也會被動到"
        let present = Self.bannedLiterals.filter { withLeak.contains($0) }
        #expect(present.contains("~/.claude"), "混進 ~/.claude 字面之後，禁字檢查應該抓到它")
    }

    /// T25（真機事故）：垃圾桶動作在無法解釋的情況下沒有真的落地，而對話框原文
    /// 「移到垃圾桶後，清空垃圾桶之前都可以救回來」是無條件保證——對那次的使用者是假話。
    /// 這個保證做出的時間點在動作**之前**（對話框是事前顯示），沒辦法等 recycle 真的
    /// 回報成功才講這句話，所以選擇把文案改成不做絕對承諾，而不是把承諾綁在事實上。
    @Test("結尾不做無條件保證——垃圾桶救援的說法要有保留，不是「一定」")
    func recoveryClaimIsHedgedNotAbsolute() {
        #expect(!UninstallConfirmation.body.contains("都可以救回來"), """
            「都可以救回來」是無條件保證——recycle 失敗時對使用者是假話（T25 實機事故）。
            文案應該用保留字眼淡化保證的絕對性，不承諾一定救得回來
            """)
        #expect(UninstallConfirmation.body.contains("通常"), "應該用「通常」之類的保留字眼淡化保證的絕對性")
    }
}
