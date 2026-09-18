import Testing
import AuraCore

/// codex-support T02：`Agent`／`AgentArgument`（spec §3／§4.1／D-b／D-c／D-d）。
///
/// CX7 的定義域是 `AgentArgvFixtures.cases`（T01／T02 review 備妥，8 格，期望值寫死），
/// 兩邊測試共用同一張表，不另寫一份（見該檔 doc comment）。
/// CX9（`claudeStateFileHasNoAgentKey`）要到 T05 的 `MergeRules.merge(agent:)` 落地後
/// 才能觀測完整的狀態檔位元組；這裡先直接對 `storedRawValue` 打先行測試，
/// 把「.claude 不寫欄位、.codex 寫 `"codex"`」的單一機制釘住。
///
/// 刻意不用 `@testable import`：`Agent`／`AgentArgument` 是跨 module 契約
/// （`aura-hook`、`AgentAuraApp` 都消費），測試要從 `public` 面看它們，否則
/// `public` 退化成 `internal` 時測試照綠、生產端編不過。
@Suite("Agent 與 --agent 參數解析")
struct AgentArgumentTests {

    /// CX7：`AgentArgument.agent(from:)` 逐格符合 `AgentArgvFixtures` 的期望 rawValue。
    /// 由左至右第一個匹配者勝、大小寫敏感、未知一律 `.claude`（D-b／D-d）。
    @Test("argv 八格表逐格斷言（CX7）")
    func agentArgumentParsing() {
        #expect(!AgentArgvFixtures.cases.isEmpty, "CX7 的定義域不能空跑")
        for testCase in AgentArgvFixtures.cases {
            let result = AgentArgument.agent(from: testCase.argv)
            #expect(result.rawValue == testCase.expectedRawValue,
                    "\(testCase.name)：argv \(testCase.argv) 應解析成 \(testCase.expectedRawValue)，實際 \(result.rawValue)")
        }
    }

    /// `Agent.init(stored:)` 對 `nil`／未知字串一律落回 `.claude`（D-b），
    /// 大小寫敏感、已知字串才解析成對應 case。
    @Test("init(stored:) 對 nil／未知／大小寫不符一律落回 .claude")
    func initFromStoredFallsBackToClaudeForUnknown() {
        #expect(Agent(stored: nil) == .claude)
        #expect(Agent(stored: "gemini") == .claude)
        #expect(Agent(stored: "CODEX") == .claude, "大小寫不匹配也要落回 .claude")
        #expect(Agent(stored: "") == .claude)
        #expect(Agent(stored: "claude") == .claude)
        #expect(Agent(stored: "codex") == .codex)
    }

    /// CX9 先行測試：`storedRawValue` 是「`.claude` 不寫欄位」這個不變式的唯一機制。
    /// 完整的狀態檔位元組驗證在 T05 之後的 `claudeStateFileHasNoAgentKey`（CX9）。
    @Test(".claude 的 storedRawValue 為 nil、.codex 為 \"codex\"（D-c／CX9 先行）")
    func storedRawValueOmitsClaudeButKeepsCodex() {
        #expect(Agent.claude.storedRawValue == nil)
        #expect(Agent.codex.storedRawValue == "codex")
    }

    /// `label`：`.claude` 不顯示任何標籤；`.codex` 固定顯示產品名 "Codex"，
    /// 刻意不進 `L10n*` 字串表（D-l／spec §3）。
    @Test("label：.claude 為 nil、.codex 為 \"Codex\"")
    func labelOnlyForCodex() {
        #expect(Agent.claude.label == nil)
        #expect(Agent.codex.label == "Codex")
    }
}
