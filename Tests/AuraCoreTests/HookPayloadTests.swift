import Testing
import Foundation
@testable import AuraCore

@Suite("HookPayload 容錯解析（§2.1.1）")
struct HookPayloadTests {

    // ---- 真實 payload ----

    @Test("解析全部 33 個真實 payload 都不回 nil")
    func parsesAllRealPayloads() throws {
        let all = try Fixtures.rawEvents(named: "round1") + Fixtures.rawEvents(named: "round1b")
        #expect(all.count == 33)
        for json in all {
            #expect(HookPayload(json: json) != nil,
                    "真實 payload 解析失敗：\(json["hook_event_name"] ?? "?")")
        }
    }

    @Test("effort 物件形狀 {\"level\":\"xhigh\"} 攤平成字串")
    func effortObjectFlattened() throws {
        let pre = try #require(try Fixtures.events(named: "round1", kind: "PreToolUse").first)
        let p = try #require(HookPayload(json: pre))
        #expect(p.effortLevel == "xhigh")
    }

    @Test("effort 也接受字串形狀（防上游改格式）")
    func effortStringAccepted() throws {
        let p = try #require(HookPayload(json: [
            "hook_event_name": "PreToolUse", "session_id": "s1", "effort": "high",
        ]))
        #expect(p.effortLevel == "high")
    }

    @Test("effort 是意外型別時回 nil，不得 crash")
    func effortWeirdType() throws {
        for weird: Any in [42, [1, 2, 3], ["nope": "x"], NSNull()] {
            let p = try #require(HookPayload(json: [
                "hook_event_name": "PreToolUse", "session_id": "s1", "effort": weird,
            ]))
            #expect(p.effortLevel == nil)
        }
    }

    @Test("SessionEnd 的結束原因讀 reason，也向後容忍 end_reason")
    func reasonFieldTolerance() throws {
        let a = try #require(HookPayload(json: [
            "hook_event_name": "SessionEnd", "session_id": "s1", "reason": "clear",
        ]))
        #expect(a.reason == "clear")

        let b = try #require(HookPayload(json: [
            "hook_event_name": "SessionEnd", "session_id": "s1", "end_reason": "exit",
        ]))
        #expect(b.reason == "exit", "文件寫 end_reason、實測是 reason —— 兩者都要能讀")
    }

    // ---- 主 agent vs subagent（§2.5 的判別依據）----

    @Test("agent_id 為 null 是主 agent，非 null 是 subagent")
    func subagentDetection() throws {
        let all = try Fixtures.rawEvents(named: "round1") + Fixtures.rawEvents(named: "round1b")
        let payloads = all.compactMap { HookPayload(json: $0) }
        let subs = payloads.filter(\.isSubagent)
        let mains = payloads.filter { !$0.isSubagent }
        #expect(subs.count == 18, "實測 18 個 subagent 事件")
        #expect(mains.count == 15, "實測 15 個主 agent 事件")
        #expect(subs.allSatisfy { $0.agentType == "implementer" })
    }

    @Test("subagent 與主 agent 共用同一個 session_id（覆蓋 bug 的根源）")
    func subagentSharesSessionID() throws {
        let all = try Fixtures.rawEvents(named: "round1b")
        let payloads = all.compactMap { HookPayload(json: $0) }
        let ids = Set(payloads.map(\.sessionID))
        #expect(ids.count == 1, "同一 session 內主/subagent 共用 session_id")
        #expect(payloads.contains { $0.isSubagent })
        #expect(payloads.contains { !$0.isSubagent })
    }

    // ---- 對抗式：畸形輸入 ----

    @Test("缺少 hook_event_name 或 session_id 時回 nil")
    func missingRequiredFields() {
        #expect(HookPayload(json: ["session_id": "s1"]) == nil)
        #expect(HookPayload(json: ["hook_event_name": "Stop"]) == nil)
        #expect(HookPayload(json: [:]) == nil)
    }

    @Test("session_id 型別錯誤時回 nil")
    func sessionIDWrongType() {
        #expect(HookPayload(json: ["hook_event_name": "Stop", "session_id": 12345]) == nil)
        #expect(HookPayload(json: ["hook_event_name": "Stop", "session_id": NSNull()]) == nil)
    }

    @Test("多出未知欄位不影響解析")
    func unknownFieldsIgnored() throws {
        let p = try #require(HookPayload(json: [
            "hook_event_name": "PreToolUse", "session_id": "s1",
            "brand_new_field_2027": ["nested": [1, 2, 3]],
            "another": true,
        ]))
        #expect(p.sessionID == "s1")
    }

    @Test("截斷的 JSON bytes 回 nil，不得 crash")
    func truncatedJSON() throws {
        let full = try Fixtures.jsonData(try #require(try Fixtures.rawEvents(named: "round1").first))
        for cut in [0, 1, full.count / 3, full.count / 2, full.count - 1] {
            #expect(HookPayload(data: full.prefix(cut)) == nil)
        }
    }

    @Test("非 JSON 或非物件的 bytes 回 nil")
    func nonObjectJSON() {
        for s in ["", "   ", "null", "[]", "[1,2,3]", "\"hello\"", "42", "{", "}{", "not json at all"] {
            #expect(HookPayload(data: Data(s.utf8)) == nil, "輸入 \(s.debugDescription) 應回 nil")
        }
    }

    @Test("unicode / emoji / 超長 cwd 都能解析")
    func exoticStrings() throws {
        let long = String(repeating: "深/", count: 600)
        let p = try #require(HookPayload(json: [
            "hook_event_name": "PreToolUse", "session_id": "s1",
            "cwd": "/Users/you/專案 🚀/\(long)", "tool_name": "Bash",
        ]))
        #expect(p.cwd?.contains("🚀") == true)
        #expect((p.cwd?.count ?? 0) > 1000)
    }

    @Test("agent_type 空字串正規化為 nil（內部 subagent，§2.5.1）")
    func emptyAgentTypeNormalized() throws {
        let p = try #require(HookPayload(json: [
            "hook_event_name": "SubagentStop", "session_id": "s1",
            "agent_id": "a8c360a1fe475f199", "agent_type": "",
        ]))
        #expect(p.isSubagent, "agent_id 有值 → 仍是 subagent 事件")
        #expect(p.agentType == nil, "空字串不得成為 subagents 的鍵")
    }

    @Test("round2 的真實內部 subagent payload 解析後 agentType 為 nil")
    func realInternalSubagentParsed() throws {
        let stops = try Fixtures.events(named: "round2", kind: "SubagentStop")
        let internals = stops.compactMap { HookPayload(json: $0) }
            .filter { $0.agentType == nil && $0.isSubagent }
        #expect(!internals.isEmpty, "實測確實有 agent_type 為空字串的 subagent")
    }

    @Test("PostModelSwitch 的 to_model 被當成 model 讀出來")
    func modelFromPostModelSwitch() throws {
        let p = try #require(HookPayload(json: [
            "hook_event_name": "PostModelSwitch", "session_id": "s1",
            "from_model": "claude-sonnet-5", "to_model": "claude-opus-5",
        ]))
        #expect(p.model == "claude-opus-5", "使用者中途 /model 換模型，面板不得顯示舊模型")
        #expect(p.effect == .noChange, "換模型不改變 activity")
    }

    @Test("SessionStart 的 model 被讀出來，其他 event 沒有")
    func modelFromSessionStart() throws {
        let starts = try Fixtures.events(named: "round2", kind: "SessionStart")
        let first = try #require(starts.first)
        let p = try #require(HookPayload(json: first))
        #expect(p.model?.hasPrefix("claude") == true, "實測值形如 claude-opus-5[1m]")
        let pre = try #require(HookPayload(json: ["hook_event_name": "PreToolUse", "session_id": "s1"]))
        #expect(pre.model == nil)
    }

    @Test("Notification 的 message 欄位被讀出來，且缺 permission_mode/effort 也能解析")
    func notificationFields() throws {
        let notifs = try Fixtures.events(named: "round2", kind: "Notification")
        let json = try #require(notifs.first)
        #expect(json["permission_mode"] == nil, "實測：Notification 不帶此欄位")
        #expect(json["effort"] == nil)
        let p = try #require(HookPayload(json: json))
        #expect(p.notificationType == "idle_prompt")
        #expect(p.notificationMessage?.isEmpty == false)
        #expect(p.permissionMode == nil)
        #expect(p.effortLevel == nil)
    }

    @Test("tool_input.description 被讀出來，缺少或型別錯時回 nil")
    func toolDescriptionExtraction() throws {
        let reqs = try Fixtures.events(named: "round2", kind: "PermissionRequest")
        let first = try #require(reqs.first)
        let p = try #require(HookPayload(json: first))
        #expect(p.toolDescription?.isEmpty == false,
                "實測 PermissionRequest 的 tool_input 帶 description")

        // tool_input 缺失、非物件、description 缺失、description 非字串 —— 都不得 crash
        for weird: Any in [NSNull(), "not a dict", 42, [1, 2], ["other": "x"], ["description": 7]] {
            let q = try #require(HookPayload(json: [
                "hook_event_name": "PreToolUse", "session_id": "s1", "tool_input": weird,
            ]))
            #expect(q.toolDescription == nil)
        }
        let r = try #require(HookPayload(json: [
            "hook_event_name": "PreToolUse", "session_id": "s1",
        ]))
        #expect(r.toolDescription == nil, "完全沒有 tool_input")
    }

    @Test("PermissionRequest 的實測欄位（含 permission_suggestions）")
    func permissionRequestFields() throws {
        let reqs = try Fixtures.events(named: "round2", kind: "PermissionRequest")
        #expect(!reqs.isEmpty, "Task 01 第三輪必須捕獲")
        let json = try #require(reqs.first)
        #expect(json["permission_mode"] as? String == "default",
                "CLI 的 --permission-mode manual 在 payload 裡是 default")
        #expect(json["permission_suggestions"] != nil, "實測發現的額外欄位")
        let p = try #require(HookPayload(json: json))
        #expect(p.effect == .setActivity(.waiting))
        #expect(p.toolName == "Bash")
    }

    @Test("SessionEnd 的實測 reason 值")
    func sessionEndReason() throws {
        let ends = try Fixtures.events(named: "round2", kind: "SessionEnd")
        #expect(!ends.isEmpty)
        let first = try #require(ends.first)
        let p = try #require(HookPayload(json: first))
        #expect(p.reason == "prompt_input_exit", "實測值")
        #expect(p.effect == .sessionEnded)
    }

    @Test("effect 直接委派給 EventMapping，含 notification_type")
    func effectDelegation() throws {
        let a = try #require(HookPayload(json: [
            "hook_event_name": "Notification", "session_id": "s1",
            "notification_type": "agent_completed",
        ]))
        #expect(a.effect == .setActivity(.done))

        let b = try #require(HookPayload(json: [
            "hook_event_name": "Notification", "session_id": "s1",
            "notification_type": "auth_success",
        ]))
        #expect(b.effect == .noChange)
    }

    // ---- 欄位覆蓋率自我推導（不靠手列清單）----

    /// 手列清單版本（上面每一個測試）漏掉 `agentID`/`lastMessage`/`source`/`toolDurationMs`
    /// 四個欄位「值是否真的被解析出來」的斷言。這裡改成對每個宣告欄位定義「原始 JSON
    /// 有沒有帶值」的判定式，掃過三份真實 fixture 全部 141 筆 payload：原始鍵有合法值時，
    /// 對應屬性就不能是 nil —— 抓「讀錯鍵名/轉型寫錯導致欄位永遠讀不出來」這種
    /// 一路綠燈也不會被發現的錯，並斷言每個欄位在真實資料裡至少命中一次。
    @Test("每個宣告欄位在真實 payload 裡都真的被解析出值（自我推導覆蓋率）")
    func perFieldTolerance() throws {
        struct FieldProbe {
            let name: String
            let hasRawValue: ([String: Any]) -> Bool
            let propertyValue: (HookPayload) -> Any?
        }

        let probes: [FieldProbe] = [
            .init(name: "cwd", hasRawValue: { ($0["cwd"] as? String)?.isEmpty == false }, propertyValue: { $0.cwd }),
            .init(name: "permissionMode", hasRawValue: { ($0["permission_mode"] as? String)?.isEmpty == false }, propertyValue: { $0.permissionMode }),
            .init(name: "source", hasRawValue: { ($0["source"] as? String)?.isEmpty == false }, propertyValue: { $0.source }),
            .init(name: "reason", hasRawValue: { (($0["reason"] as? String) ?? ($0["end_reason"] as? String))?.isEmpty == false }, propertyValue: { $0.reason }),
            .init(name: "toolName", hasRawValue: { ($0["tool_name"] as? String)?.isEmpty == false }, propertyValue: { $0.toolName }),
            .init(name: "toolDescription", hasRawValue: { (($0["tool_input"] as? [String: Any])?["description"] as? String)?.isEmpty == false }, propertyValue: { $0.toolDescription }),
            .init(name: "toolDurationMs", hasRawValue: { $0["duration_ms"] is Int }, propertyValue: { $0.toolDurationMs }),
            .init(name: "model", hasRawValue: { (($0["model"] as? String) ?? ($0["to_model"] as? String))?.isEmpty == false }, propertyValue: { $0.model }),
            .init(name: "notificationType", hasRawValue: { ($0["notification_type"] as? String)?.isEmpty == false }, propertyValue: { $0.notificationType }),
            .init(name: "notificationMessage", hasRawValue: { ($0["message"] as? String)?.isEmpty == false }, propertyValue: { $0.notificationMessage }),
            .init(name: "lastMessage", hasRawValue: { ($0["last_assistant_message"] as? String)?.isEmpty == false }, propertyValue: { $0.lastMessage }),
            .init(name: "agentID", hasRawValue: { ($0["agent_id"] as? String)?.isEmpty == false }, propertyValue: { $0.agentID }),
            .init(name: "agentType", hasRawValue: { ($0["agent_type"] as? String)?.isEmpty == false }, propertyValue: { $0.agentType }),
        ]

        let all = try Fixtures.rawEvents(named: "round1")
            + Fixtures.rawEvents(named: "round1b")
            + Fixtures.rawEvents(named: "round2")
        #expect(all.count == 141)

        var exercised: Set<String> = []
        var combinations = 0
        for json in all {
            guard let p = HookPayload(json: json) else {
                Issue.record("真實 payload 解析失敗：\(json["hook_event_name"] ?? "?")")
                continue
            }
            for probe in probes where probe.hasRawValue(json) {
                combinations += 1
                #expect(probe.propertyValue(p) != nil,
                        "\(probe.name) 原始值存在卻沒被解析出來（event: \(json["hook_event_name"] ?? "?"))")
                exercised.insert(probe.name)
            }
        }

        for probe in probes {
            #expect(exercised.contains(probe.name),
                    "真實 fixture 裡沒有任何 payload 讓 \(probe.name) 有值 —— 這個欄位的覆蓋率是空的")
        }
        #expect(combinations > 0)
    }
}
