import Testing
import Foundation
@testable import AuraCore

/// T04b：`CodexHookPathCheck`——R-5 三個消費者共用的單一路徑判定，spec §4.4／CX33。
@Suite("CodexHookPathCheck 指名冒犯字元（CX33）")
struct CodexHookPathCheckTests {

    /// 把真正算出來的 `Rejection?` 轉成與 `CodexPathFixtures.Case.expectedRejection`
    /// 同樣的字串描述——T01 review M1 的協定：期望值寫死在 fixture 裡、不是從實作反推，
    /// 兩邊比對時由這裡把型別轉成字串，而不是反過來把 fixture 改成吃 `Rejection`。
    private static func describe(_ rejection: CodexHookPathCheck.Rejection?) -> String? {
        switch rejection {
        case nil: nil
        case .mustMoveToApplications: "mustMoveToApplications"
        case let .unsupportedCharacter(c): "unsupportedCharacter(\(c))"
        }
    }

    @Test("CodexPathFixtures 定義域非空")
    func fixtureDomainIsNonEmpty() {
        #expect(!CodexPathFixtures.cases.isEmpty)
    }

    /// 定義域＝`CodexPathFixtures.cases`（T01，十格，期望值寫死不從實作反推）逐格比對。
    @Test("CodexPathFixtures 十格逐格比對")
    func matchesPathFixturesVerbatim() {
        for testCase in CodexPathFixtures.cases {
            let result = CodexHookPathCheck.rejection(
                translocated: testCase.translocated,
                inDownloads: testCase.inDownloads,
                hookBinaryPath: testCase.hookBinaryPath)
            #expect(Self.describe(result) == testCase.expectedRejection,
                    "\(testCase.name)：預期 \(testCase.expectedRejection ?? "nil")，實際 \(Self.describe(result) ?? "nil")")
        }
    }

    /// 另從**生產常數** `unsupportedCharacters` 推導逐字元格——與上面用 fixture 寫死的
    /// 六個字元是兩條獨立的線：這一條保證未來 `unsupportedCharacters` 若真的多一個字元，
    /// 這裡自動涵蓋它，不必記得回來加一格 fixture。
    @Test("unsupportedCharacters 逐字元推導格")
    func matchesEveryProductionUnsupportedCharacter() {
        #expect(!CodexHookPathCheck.unsupportedCharacters.isEmpty, "定義域不能空跑")
        // 六個原始字元 ＋ M3 新增的換行、tab——這條從生產常數自動推導出 8 格，
        // 不必回來手改這條測試；數字本身只是佐證，真正的守衛是下面的逐字元迴圈。
        #expect(CodexHookPathCheck.unsupportedCharacters.count == 8,
                "spec-reviewer M3 之後應為 8 個字元（原六個 ＋ 換行、tab）")
        for character in CodexHookPathCheck.unsupportedCharacters {
            let path = "/Applications/Agent\(character)Aura.app/Contents/MacOS/aura-hook"
            let result = CodexHookPathCheck.rejection(
                translocated: false, inDownloads: false, hookBinaryPath: path)
            #expect(result == .unsupportedCharacter(character),
                    "字元 \(character) 應被判定為 unsupportedCharacter，實際 \(String(describing: result))")
        }
    }

    /// spec-reviewer M3（裁決）：原本六個字元擋不住換行與 tab，而兩種解析假設下
    /// （command 交給 shell，或只是單純用空白切分參數）它們都會出問題，且合法路徑幾乎
    /// 不會用到——加了零過度拒絕代價。寫死字面（不是從 `unsupportedCharacters` 推導）：
    /// 這條要能在有人把它們從生產常數移除時紅，而不是隨生產常數一起消失。
    @Test("換行與 tab 各自被判定為 unsupportedCharacter")
    func newlineAndTabAreRejected() {
        let mustReject: [Character] = ["\n", "\t"]
        for character in mustReject {
            let path = "/Applications/Agent\(character)Aura.app/Contents/MacOS/aura-hook"
            let result = CodexHookPathCheck.rejection(
                translocated: false, inDownloads: false, hookBinaryPath: path)
            #expect(result == .unsupportedCharacter(character),
                    "字元 \(character.debugDescription) 應被判定為 unsupportedCharacter，實際 \(String(describing: result))")
        }
    }

    /// 第一個命中者勝：路徑裡有兩個不支援字元時，回傳的是**由左至右**第一個。
    @Test("多個不支援字元時回傳由左至右第一個")
    func returnsFirstOffendingCharacterLeftToRight() {
        // 路徑裡先出現空白（較前的 index），再出現雙引號——預期回傳空白。
        let path = "/Applications/Agent Au\"ra.app/Contents/MacOS/aura-hook"
        #expect(CodexHookPathCheck.rejection(translocated: false, inDownloads: false,
                                             hookBinaryPath: path) == .unsupportedCharacter(" "))
    }

    /// `RejectionKind.allCases` 逐一 `samples(_:)` 非空、且每個代表值的 `kind` 回指自己——
    /// D-r 的窮盡定義域推導鏈（`CodexState.samples(.blockedByBundlePath)`（T07）就是靠這條
    /// 非空保證推出來的）。
    @Test("每個 RejectionKind 的 samples 非空且 kind 回指自己")
    func everyRejectionKindHasNonEmptySamples() {
        #expect(!CodexHookPathCheck.RejectionKind.allCases.isEmpty)
        for kind in CodexHookPathCheck.RejectionKind.allCases {
            let samples = CodexHookPathCheck.Rejection.samples(kind)
            #expect(!samples.isEmpty, "\(kind) 的 samples 不能是空陣列")
            for sample in samples {
                #expect(sample.kind == kind, "\(sample) 的 kind 應為 \(kind)")
            }
        }
    }
}
