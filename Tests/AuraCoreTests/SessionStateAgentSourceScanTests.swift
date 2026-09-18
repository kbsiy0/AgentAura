import Testing
import Foundation

/// T05d m1（review）：`SessionState.init` 的 `agent: Agent = .claude` 帶預設值是
/// **對齊既有慣例**（`toolDescription`／`notificationMessage` 早就是這樣，見
/// `SessionState.swift` 的 doc comment），不是 tested≠wired——生產建構點只有一處
/// （`SessionReducer.swift`）且**明傳** `agent: Agent(stored: s.agent)`，`AgentThreadingTests`
/// 的四段貫穿測試走的是真生產函式鏈，拿掉那行明傳會讓
/// `agentFlowsThroughStateAndPanelRowCodex` 立刻紅。
///
/// 殘餘缺口只有一個方向：**未來新增第二個生產建構點時，忘了傳 `agent:` 會靜默落回
/// `.claude`**，而所有既有測試都不會抓到——因為它們早就靠這個預設值運作。這條 gate
/// 補的就是這個方向：`Sources/` 底下 `SessionState(` 的建構呼叫恰好一處，且那一處
/// 必須明傳 `agent:`。加第二個生產建構點時，這條 gate 會逼著新的呼叫點也表態。
@Suite("SessionState 生產建構點必須明傳 agent（sessionStateProductionConstructionSitesPassAgent）")
struct SessionStateAgentSourceScanTests {

    @Test("Sources/ 底下 SessionState( 恰有一處建構呼叫，且該處明傳 agent:")
    func sessionStateProductionConstructionSitesPassAgent() throws {
        let root = Gate.repoRoot().appendingPathComponent("Sources")
        let (scanned, occurrences) = try SessionStateConstructionSourceScan.scan(under: root)
        #expect(scanned >= 3, "Sources/ 只讀到 \(scanned) 個 .swift —— gate 不能空跑")
        #expect(occurrences.count == 1, """
            Sources/ 底下 SessionState( 的建構呼叫應恰為 1 處（目前只有
            SessionReducer.state(from:liveness:)），實際找到 \(occurrences.count) 處：
            \(occurrences.map { "\($0.file.lastPathComponent)" })。
            新增生產建構點時必須明傳 agent，預設值只服務測試——多一個建構點就要重新
            檢視這條 gate 的斷言方式（例如逐一檢查每一處）。
            """)
        if let only = occurrences.first {
            #expect(only.block.contains("agent:"), """
                \(only.file.lastPathComponent) 裡的 SessionState( 建構呼叫沒有明傳
                agent:——新增生產建構點時必須明傳 agent，預設值只服務測試，不能靜默
                落回 .claude。呼叫區塊：
                \(only.block)
                """)
        }
    }

    /// 正向對照（沿用 `HookVerificationStoreSourceScanTests` 的既有慣例）：暫存目錄
    /// 放兩個 probe，一個明傳 `agent:`、一個沒有，同一個 scanner 必須各自正確判斷——
    /// 沒有這條，上面「occurrences.count == 1」與「block.contains("agent:")」在
    /// 解析壞掉時也可能安靜綠。
    @Test("正向對照：scanner 正確抓到多處建構呼叫，且逐一判斷有沒有明傳 agent:")
    func scanCatchesMultipleConstructionSitesAndDistinguishesAgent() throws {
        try Gate.withTemporaryDirectory { dir in
            let withAgent = dir.appendingPathComponent("WithAgent.swift")
            try """
                enum Probe {
                    static func makeCodex() -> SessionState {
                        SessionState(
                            id: "x", projectName: "p",
                            permissionMode: nil, effort: nil, model: nil,
                            agent: .codex,
                            activity: .idle, mainActivity: .idle, subActivity: nil,
                            currentTool: nil, subagentTool: nil, toolDurationMs: nil,
                            turnStartedAt: nil, subagents: [:], toolFailures: 0,
                            lastMessage: nil, errorType: nil, toolError: nil,
                            liveness: .ended, updatedAt: .distantPast)
                    }
                }
                """.write(to: withAgent, atomically: true, encoding: .utf8)

            let withoutAgent = dir.appendingPathComponent("WithoutAgent.swift")
            try """
                enum Probe2 {
                    static func makeDefault() -> SessionState {
                        SessionState(
                            id: "y", projectName: "p",
                            permissionMode: nil, effort: nil, model: nil,
                            activity: .idle, mainActivity: .idle, subActivity: nil,
                            currentTool: nil, subagentTool: nil, toolDurationMs: nil,
                            turnStartedAt: nil, subagents: [:], toolFailures: 0,
                            lastMessage: nil, errorType: nil, toolError: nil,
                            liveness: .ended, updatedAt: .distantPast)
                    }
                }
                """.write(to: withoutAgent, atomically: true, encoding: .utf8)

            let (scanned, occurrences) = try SessionStateConstructionSourceScan.scan(under: dir)
            #expect(scanned == 2, "解析沒抓到暫存目錄的兩個 probe 檔")
            #expect(occurrences.count == 2, """
                scanner 沒有抓到兩處 SessionState( 建構呼叫——解析壞了會讓生產端的
                「恰為 1 處」檢查在漏抓時也安靜綠
                """)
            let withAgentCount = occurrences.filter { $0.block.contains("agent:") }.count
            #expect(withAgentCount == 1, """
                scanner 應該只判定一個 probe 明傳 agent:，實際 \(withAgentCount) 個——
                解析壞了會讓「block.contains(agent:)」失去分辨力
                """)
        }
    }
}
