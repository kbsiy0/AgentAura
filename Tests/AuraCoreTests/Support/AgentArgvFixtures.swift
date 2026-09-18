import Foundation

/// codex-support T01 必辦⑥：`--agent` 的 argv 對抗式表（spec §6.1(2)），**CX7 與 CX8
/// 共用的唯一來源**——期望值寫死在這裡，不是從 `AgentArgument.agent(from:)`（T02 才存在）
/// 反推。`expectedRawValue` 用字串（"claude"／"codex"）而不是 `Agent` enum 本身，
/// 讓這張表在 T02 落地前也能先編譯、先被別的 fixture 引用。
enum AgentArgvFixtures {
    struct Case {
        let name: String
        let argv: [String]
        /// 期望的 `Agent.init(stored:)?.rawValue`／`AgentArgument.agent(from:).rawValue`。
        let expectedRawValue: String
    }

    /// 七格，由左至右第一個匹配者勝、大小寫敏感、未知一律 `.claude`（D-b／D-d）。
    static let cases: [Case] = [
        Case(name: "空 argv", argv: [], expectedRawValue: "claude"),
        Case(name: "--agent 缺值", argv: ["--agent"], expectedRawValue: "claude"),
        Case(name: "--agent gemini（未知值）", argv: ["--agent", "gemini"], expectedRawValue: "claude"),
        Case(name: "--agent CODEX（大小寫不匹配）", argv: ["--agent", "CODEX"], expectedRawValue: "claude"),
        Case(name: "--agent=codex（等號寫法）", argv: ["--agent=codex"], expectedRawValue: "codex"),
        Case(name: "重複兩次，codex 在前", argv: ["--agent", "codex", "--agent", "claude"],
             expectedRawValue: "codex"),
        Case(name: "codex 在前、後面一個缺值的 --agent",
             argv: ["--agent", "codex", "--agent"], expectedRawValue: "codex"),
    ]
}
