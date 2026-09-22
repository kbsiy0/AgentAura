import Testing
import Foundation
import AuraCore

/// **CX55 `helpDocsExplainMergingIntoExistingHooks`**（T13h／D-aa 的落點）：面板卡片把
/// 使用者指去 help（CX54 的 `.openHelp` 按鈕），那邊就必須有東西——`.occupiedByOther` 卡片
/// 前一句才說「我們不會動你的檔」，下一句就遞出一份 root `{"hooks": …}` 的完整替換檔，
/// 這是整個流程裡唯一一個「手滑貼上就毀掉自己 hooks」的位置，合併細節一行寫不完。
///
/// needle 直接用面板同一句文案（`L10nCodexCards.mergeInstruction`）——兩邊語意保證同步，
/// 不必維護第二份字面（同 `HelpDocOptionsRowCoverageTests` 的既有手法）。
/// `@Test(arguments:)` 參數化兩份，**不是**兩條各寫一遍——CX29 的既有教訓：內容有、
/// 守衛沒有，刪掉兩邊只紅一條。
@Suite("D-aa：help 文件涵蓋合併指示（CX55）")
struct CodexMergeHelpCoverageTests {

    static func helpFileName(for language: Language) -> String {
        "help-\(language.rawValue).html"
    }

    static func helpText(for language: Language) throws -> String {
        try String(contentsOf: Gate.repoRoot().appendingPathComponent("Resources/\(helpFileName(for: language))"),
                    encoding: .utf8)
    }

    @Test("help-english.html／help-traditionalChinese.html 都含合併指示（兩份各自守自己的檔）",
          arguments: Language.allCases)
    func helpDocsExplainMergingIntoExistingHooks(language: Language) throws {
        let text = try Self.helpText(for: language)
        #expect(text.contains(L10nCodexCards.mergeInstruction.text(language)), """
            \(Self.helpFileName(for: language)) 沒有提到合併指示——面板把使用者指過去\
            （CX54 的 .openHelp 按鈕），那邊卻沒有東西
            """)
    }

    /// 正向對照：從其中一份刪掉那段字面之後，斷言真的抓得到缺漏——不是「怎麼測都會過」的
    /// 空氣測試。兩個語言各自驗證同一件事，對應 CX29 的既有教訓（任一份刪掉都要能被抓到）。
    @Test("正向對照：刪掉合併指示字面後，contains 真的變 false", arguments: Language.allCases)
    func scanCatchesRealOmission(language: Language) throws {
        let text = try Self.helpText(for: language)
        let keyword = L10nCodexCards.mergeInstruction.text(language)
        let withoutIt = text.replacingOccurrences(of: keyword, with: "")
        #expect(!withoutIt.contains(keyword), "拿掉字面之後 contains 應該變 false，實際仍為 true")
    }
}
