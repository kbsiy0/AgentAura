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

    /// 八格，由左至右**第一個出現者勝**（不是「第一個有效者勝」）、大小寫敏感、
    /// 未知一律 `.claude`（D-b／D-d）。第 8 格（T02 review）是「第一個出現者勝」與
    /// 「第一個有效者勝」這兩種語意唯一分得出來的輸入：前七格裡不管哪一種語意都給
    /// 同一個答案，換一個替代實作（挑第一個有效值）跑一樣會全綠。裁決理由：
    /// 「第一個有效者勝」等於讓使用者手寫錯的第一個旗標被後面悄悄蓋過，
    /// 違反 D-b 的保守失敗原則（寧可少一個標籤、不可把 Codex 標成 Claude 或反過來）。
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
        Case(name: "第一個 --agent 是未知值、後面還有一個有效的（釘住『第一個出現者勝』，不是『第一個有效者勝』）",
             argv: ["--agent", "gemini", "--agent", "codex"], expectedRawValue: "claude"),
    ]
}
