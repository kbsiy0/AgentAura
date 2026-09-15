import Testing
import Foundation

/// `L10nLiteralScan` 自我驗證——同 `UserDefaultsSourceScanShapeTests` 的精神：先證明
/// 掃描機制本身分得清「字串字面裡的中文」跟「註解裡的中文」，D-5(3) 的正式 gate
/// 才可信。這條合理地是 GREEN（驗的是掃描器，不是還沒搬的生產碼）。
@Suite("L10nLiteralScan 自我驗證")
struct L10nLiteralScanShapeTests {

    @Test("正向對照：字串字面裡的中文會被抓到")
    func catchesCJKInStringLiteral() {
        let source = "let x = \"你好\"\n"
        #expect(L10nLiteralScan.fileHasCJKStringLiteral(source))
    }

    @Test("負對照：只在 // 註解裡的中文不會被抓到")
    func doesNotFlagCommentOnlyCJK() {
        let source = "// 這是註解，含中文，但不是字串字面\nlet x = 1\n"
        #expect(!L10nLiteralScan.fileHasCJKStringLiteral(source))
    }

    @Test("負對照：純 ASCII 字串字面不會被抓到")
    func doesNotFlagASCIIStringLiteral() {
        let source = "let x = \"hello\"  // 中文只在註解裡\n"
        #expect(!L10nLiteralScan.fileHasCJKStringLiteral(source))
    }

    @Test("同一行裡，字串字面後面的 // 註解中文不算，字串字面本身的中文才算")
    func perLineCommentStrippedBeforeScanningLiteral() {
        let onlyCommentHasCJK = "let x = \"hello\"  // 中文\n"
        let literalHasCJK = "let x = \"你好\"  // comment\n"
        #expect(!L10nLiteralScan.fileHasCJKStringLiteral(onlyCommentHasCJK))
        #expect(L10nLiteralScan.fileHasCJKStringLiteral(literalHasCJK))
    }

    @Test("跳脫的引號不會提早結束字串字面")
    func escapedQuoteDoesNotEndLiteral() {
        let source = #"let x = "前面 \" 後面有中文"#
        let source2 = source + "你好\"\n"
        #expect(L10nLiteralScan.fileHasCJKStringLiteral(source2))
    }
}
