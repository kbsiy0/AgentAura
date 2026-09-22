import Testing
import Foundation
@testable import AuraCore

/// `SessionSnapshot` 的 Codable round-trip 覆蓋。拆自 `MergeRulesTests`
/// 純粹是行數上限（Tests ≤300 行）—— 同一份 §2.5 規格，見該檔案的分槽與累積測試。
@Suite("MergeRules → SessionSnapshot Codable round-trip")
struct MergeRulesCodableTests {

    let t0 = Date(timeIntervalSince1970: 1_788_628_000)

    func payload(_ event: String, tool: String? = nil, agent: String? = nil,
                 agentType: String? = nil) -> HookPayload {
        var json: [String: Any] = ["hook_event_name": event, "session_id": "s1"]
        if let tool { json["tool_name"] = tool }
        if let agent { json["agent_id"] = agent; json["agent_type"] = agentType ?? "implementer" }
        return HookPayload(json: json)!
    }

    func merge(_ p: HookPayload, into s: SessionSnapshot?) -> SessionSnapshot {
        MergeRules.merge(p, into: s, pid: 4242, pidStartedAt: 111, agent: .claude, now: t0)
    }

    /// **CodingKeys 完整性 gate。**
    ///
    /// 刻意把**每一個** stored property 都填上與預設值不同的值再 round-trip。
    /// 若只靠幾次 merge 產生的 snapshot（原本的寫法），沒被填到的欄位即使從
    /// `CodingKeys` 漏掉，round-trip 仍會相等 —— 測不出來。這是 optional 欄位
    /// 特別危險的地方：漏掉的 key 解碼成 nil，而原值本來就是 nil。
    @Test("JSON round-trip 保留每一個 stored property")
    func codableRoundTripCoversEveryField() throws {
        var s = SessionSnapshot(sessionID: "round-trip-1")
        s.schema              = 7
        s.hookEventName       = "PermissionRequest"
        s.writtenAt           = Date(timeIntervalSince1970: 1_788_628_111)
        s.pid                 = 4242
        s.pidStartedAt        = 1_757_352_011
        s.agent               = "codex"
        s.cwd                 = "/Users/you/專案 🚀/payments-api"
        s.permissionMode      = "default"
        s.effort              = "xhigh"
        s.model               = "claude-opus-5[1m]"
        s.source              = "startup"
        s.reason              = "prompt_input_exit"
        s.mainActivity        = .waiting
        s.mainTool            = "Bash"
        s.subActivity         = .working
        s.subTool             = "Grep"
        s.subAgentType        = "Explore"
        s.outstandingSubagents = ["a0b503d0b03dbd023": .waiting]
        s.notificationType    = "idle_prompt"
        s.notificationMessage = "Claude is waiting for your input"
        s.lastMessage         = "全部完成"
        s.toolDescription     = "Download example.com to dl2.html"
        s.toolDurationMs      = 12_403
        s.toolError           = "File does not exist"
        s.turnStartedAt       = Date(timeIntervalSince1970: 1_788_628_000)
        s.subagents           = ["Explore": 2, "implementer": 1]
        s.toolFailures        = 3
        s.terminated          = true

        // 「每個欄位都不是預設值」這件事本身要被檢查，不能只寫在 doc-comment 裡。
        //
        // 這個 gate 曾經自己漏過欄位：宣稱涵蓋「每一個 stored property」，但
        // `toolError` 與 `schema` 從頭到尾沒被設值。實測把 `case toolError` 或
        // `case schema` 從 CodingKeys 移掉 —— 編譯照過，全套件 121 個測試無一變紅。
        //
        // 手寫的欄位清單會 drift，所以改用 `Mirror` 從型別本身推導：
        // 只要有任何 stored property 停在預設值，這裡就紅，並指名是哪一個。
        let blank = SessionSnapshot(sessionID: "blank")
        let mine = Array(Mirror(reflecting: s).children)
        let theirs = Array(Mirror(reflecting: blank).children)
        #expect(mine.count == theirs.count)
        for (a, b) in zip(mine, theirs) {
            #expect("\(a.value)" != "\(b.value)", """
                stored property `\(a.label ?? "?")` 沒被設成非預設值 —— 這個 gate 對它是盲的。
                把它從 CodingKeys 移掉不會有任何測試變紅。請在上面補一行設值。
                """)
        }

        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(SessionSnapshot.self, from: try enc.encode(s))
        #expect(back == s)

        // 額外確認：JSON 的 key 名都是 snake_case（檔案是人會讀的）
        let obj = try JSONSerialization.jsonObject(with: try enc.encode(s)) as? [String: Any]
        let keys = Set((obj ?? [:]).keys)
        for k in keys {
            #expect(k == k.lowercased(), "JSON key 應為 snake_case，但出現 \(k)")
        }
        #expect(keys.contains("main_activity") && keys.contains("tool_description")
                && keys.contains("notification_message") && keys.contains("pid_started_at"),
                "抽查幾個 snake_case key 確實存在")
    }

    /// **schema 相容性 gate（T23）。** `outstandingSubagents` 是新加的欄位 ——
    /// 舊版（升級前）寫的狀態檔不會有 `outstanding_subagents` 這個 key。
    ///
    /// 這條刻意**手組**一份不含新欄位的 JSON（不是拿新版 encoder 產生後再刪 key，
    /// 那樣測不出「型別本身容不容忍缺 key」，只測得出「我有沒有記得刪」）。
    /// 若欄位改成非 optional（例如 `= [:]` 的預設值），synthesized `Decodable`
    /// 仍會要求這個 key 存在，缺了就整包解碼失敗 —— `SnapshotIO.read` 用 `try?`
    /// 把失敗吞成 `nil`，使用者升級後既有 session 會從面板上消失，直到下一個
    /// hook event 幫它重寫檔案為止。
    @Test("舊版狀態檔（沒有 outstanding_subagents 欄位）仍可解碼")
    func decodesLegacySnapshotMissingOutstandingSubagentsField() throws {
        let legacyJSON = """
        {"schema":1,"session_id":"legacy-1","hook_event_name":"Stop",
         "written_at":"2026-09-01T00:00:00Z","main_activity":"done",
         "subagents":{},"tool_failures":0,"terminated":false}
        """
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let s = try dec.decode(SessionSnapshot.self, from: Data(legacyJSON.utf8))

        #expect(s.outstandingSubagents == nil, "缺欄位視同「沒有背景具名 subagent」")
        #expect(s.effectiveActivity == .done, "新欄位缺席不得影響既有燈號計算")
    }

    @Test("merge 產生的 snapshot 也能 round-trip")
    func codableRoundTripFromMerge() throws {
        var s = merge(payload("UserPromptSubmit"), into: nil)
        s = merge(payload("PermissionRequest", tool: "Bash"), into: s)
        s = merge(payload("PostToolUse", tool: "Write", agent: "a1", agentType: "Explore"), into: s)

        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(SessionSnapshot.self, from: try enc.encode(s))
        #expect(back == s)
    }

    @Test("schema 欄位固定為 1")
    func schemaVersion() {
        #expect(merge(payload("Stop"), into: nil).schema == 1)
    }
}
