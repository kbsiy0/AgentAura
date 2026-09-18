import Testing
import Foundation
@testable import AuraCore
@testable import AuraHookFile

/// codex-support T05a：`agent` 貫穿 payload → 檔案 → state → UI 四段
/// （spec §4.1／§3；`SessionState.model` 與 `toolDescription` 都曾經只走完
/// 兩段就以為做完了，這裡把四段一次寫成一組測試）。
@Suite("agent 貫穿四段（CX9／CX11／CX12）")
struct AgentThreadingTests {

    /// CX9（純函式層，T05d review M1 修正）：Claude 側（`.claude`）序列化後的狀態檔
    /// **不含** `agent` 鍵——用 round1／round1b／round2／round3 四份既有 fixture
    /// 逐筆 merge，涵蓋既有契約沒有因為新欄位而多寫任何東西。`agent.storedRawValue`
    /// 對 `.claude` 回 `nil`，`SessionSnapshot.agent` 是 Optional，synthesized
    /// `Encodable` 對 nil 用 `encodeIfPresent`，鍵直接消失——跟 `outstandingSubagents`
    /// 是同一個機制。
    ///
    /// **改用生產的 `SnapshotIO.encoder`**（原本自建一個 `JSONEncoder`）：這條驗的是
    /// 「鍵不存在」，跑得快、涵蓋四份 fixture 的每一筆，是純函式層；但序列化器若跟
    /// 生產路徑不同，這條就只是在驗自己的近似，不是驗真正會寫到磁碟的東西。跟
    /// `EndToEndWiredGateTests.claudeStateFileHasNoAgentKeyOnDisk`
    /// （生產層，真 spawn、驗真檔案位元組，只跑一次）互相點名，缺一不可：
    /// 這條保證「四份 fixture 的每一筆都不多寫鍵」，那條保證「真的走過
    /// `main.swift` → `SnapshotIO.encoder` → 檔案這條生產路徑」。
    @Test("Claude 側狀態檔序列化後不含 agent 鍵（CX9，純函式層）")
    func claudeStateFileHasNoAgentKey() throws {
        let names = ["round1", "round1b", "round2", "round3-named-subagent"]
        var checked = 0
        for name in names {
            for json in try Fixtures.rawEvents(named: name) {
                guard let data = try? Fixtures.jsonData(json),
                      let payload = HookPayload(data: data) else { continue }
                let snapshot = MergeRules.merge(payload, into: nil, pid: 4242, pidStartedAt: 111,
                                                agent: .claude, now: Date())
                let encoded = try SnapshotIO.encoder.encode(snapshot)
                let obj = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
                #expect(!obj.keys.contains("agent"),
                        "\(name) 的 \(payload.hookEventName) 序列化後含 agent 鍵，實際 \(String(describing: obj["agent"]))")
                checked += 1
            }
        }
        #expect(checked > 0, "gate 不能空跑")
    }

    /// CX11：舊版（沒有 `agent` 鍵）的狀態檔仍解得開，且落回 `.claude`
    /// （同 `decodesLegacySnapshotMissingOutstandingSubagentsField` 的既有理由——
    /// 這個欄位必須是 Optional，否則 synthesized `Decodable` 會要求 key 存在，
    /// 缺了就整包解碼失敗，使用者升級後既有 session 從面板消失）。
    @Test("無 agent 鍵的舊版狀態檔仍可解碼且落回 .claude（CX11）")
    func legacySnapshotWithoutAgentDecodes() throws {
        let legacyJSON = """
        {"schema":1,"session_id":"legacy-agent-1","hook_event_name":"Stop",
         "written_at":"2026-09-01T00:00:00Z","main_activity":"done",
         "subagents":{},"tool_failures":0,"terminated":false}
        """
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let s = try dec.decode(SessionSnapshot.self, from: Data(legacyJSON.utf8))

        #expect(s.agent == nil, "缺欄位視同 nil，不得讓解碼整包失敗")
        #expect(Agent(stored: s.agent) == .claude, "缺欄位落回 .claude（D-b）")
    }

    /// CX12：未知 `agent` 值（例如未來新增的 agent 或手誤字串）不得讓整包解碼失敗，
    /// 也不得被標成任何已知標籤——落回 `.claude`、不顯示標籤（D-b 保守失敗）。
    @Test("未知 agent 值不讓解碼失敗，且落回 .claude 不顯示標籤（CX12）")
    func unknownAgentFallsBackWithoutFailingDecode() throws {
        let json = """
        {"schema":1,"session_id":"unknown-agent-1","hook_event_name":"Stop",
         "written_at":"2026-09-01T00:00:00Z","main_activity":"done","agent":"gemini",
         "subagents":{},"tool_failures":0,"terminated":false}
        """
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let s = try dec.decode(SessionSnapshot.self, from: Data(json.utf8))

        #expect(s.agent == "gemini", "磁碟上的原始字串忠實保留——型別化解析只發生在 Agent(stored:) 邊界")
        let resolved = Agent(stored: s.agent)
        #expect(resolved == .claude, "未知值落回 .claude")
        #expect(resolved.label == nil, "落回 .claude 不顯示任何標籤")
    }

    /// 四段驗證（非 CX 編號，T05 目標本身）：`SessionSnapshot.agent`
    /// → `SessionReducer.state(from:liveness:).agent` → `PanelViewModel.rows(...).agentLabel`
    /// 一次走完，不只是型別能編過。`.claude` 與 `.codex` 各一條。
    func assertAgentFlows(_ agent: Agent, expectedLabel: String?, sessionID: String) throws {
        let payload = HookPayload(json: ["hook_event_name": "PreToolUse", "session_id": sessionID,
                                         "tool_name": "Bash"])!
        let snapshot = MergeRules.merge(payload, into: nil, pid: 4242, pidStartedAt: 111,
                                        agent: agent, now: Date())
        #expect(snapshot.agent == agent.storedRawValue)

        let state = SessionReducer.state(from: snapshot, liveness: StubLiveness(table: [4242: 111]))
        #expect(state.agent == agent, "SessionReducer 必須把 agent 帶進 SessionState")

        let row = try #require(PanelViewModel.rows(from: [state], language: .traditionalChinese).first)
        #expect(row.agentLabel == expectedLabel,
                "PanelRow.agentLabel 應為 \(String(describing: expectedLabel))，實際 \(String(describing: row.agentLabel))")
    }

    @Test("agent 從 SessionSnapshot 一路貫穿到 PanelRow.agentLabel（.claude 不顯示標籤）")
    func agentFlowsThroughStateAndPanelRowClaude() throws {
        try assertAgentFlows(.claude, expectedLabel: nil, sessionID: "flow-claude")
    }

    @Test("agent 從 SessionSnapshot 一路貫穿到 PanelRow.agentLabel（.codex 顯示 \"Codex\"）")
    func agentFlowsThroughStateAndPanelRowCodex() throws {
        try assertAgentFlows(.codex, expectedLabel: "Codex", sessionID: "flow-codex")
    }
}
