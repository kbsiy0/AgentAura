import Testing
import Foundation
@testable import AuraCore

@Suite("MergeRules 分槽與累積（§2.5）")
struct MergeRulesTests {

    let t0 = Date(timeIntervalSince1970: 1_788_628_000)

    func payload(_ event: String, tool: String? = nil, agent: String? = nil,
                 agentType: String? = nil, notif: String? = nil) -> HookPayload {
        var json: [String: Any] = ["hook_event_name": event, "session_id": "s1"]
        if let tool { json["tool_name"] = tool }
        if let agent { json["agent_id"] = agent; json["agent_type"] = agentType ?? "implementer" }
        if let notif { json["notification_type"] = notif }
        return HookPayload(json: json)!
    }

    func merge(_ p: HookPayload, into s: SessionSnapshot?, at t: Date? = nil) -> SessionSnapshot {
        MergeRules.merge(p, into: s, pid: 4242, pidStartedAt: 111, agent: .claude, now: t ?? t0)
    }

    // ---- 核心：subagent 不得蓋掉主 agent 的 waiting ----

    @Test("subagent 的 PostToolUse 不得蓋掉主 agent 的 waiting")
    func subagentCannotMaskWaiting() {
        var s = merge(payload("PermissionRequest", tool: "Bash"), into: nil)
        #expect(s.mainActivity == .waiting)

        // 20ms 後 subagent 插入事件 —— 實測的真實間隔
        s = merge(payload("PostToolUse", tool: "Write", agent: "sub1"),
                  into: s, at: t0.addingTimeInterval(0.02))

        #expect(s.mainActivity == .waiting, "主槽必須維持 waiting")
        #expect(s.subActivity == nil,
                "main 仍是 waiting（quiescent）→ subagent 事件被忽略，不寫進 sub 槽（見 subagentIgnoredWhileWaiting）")
        // S2-5：呼叫真正的 effectiveActivity，別手抄 max（那份公式漏了第三個輸入）。
        #expect(s.effectiveActivity == .waiting, "取三個輸入的 max 後仍是 waiting —— 橘燈不會消失")
    }

    @Test("主 agent 的長 tool 名不被 subagent 覆蓋")
    func mainToolNotOverwritten() {
        var s = merge(payload("PreToolUse", tool: "Bash"), into: nil)
        for i in 0..<8 {
            s = merge(payload(i.isMultiple(of: 2) ? "PreToolUse" : "PostToolUse",
                              tool: "Write", agent: "sub1"),
                      into: s, at: t0.addingTimeInterval(Double(i) + 5))
        }
        #expect(s.mainTool == "Bash", "實測情境：主 agent Bash 跑 19.5s，期間 subagent 插 8 個事件")
        #expect(s.subTool == "Write")
        #expect(s.subAgentType == "implementer")
    }

    @Test("主 agent 的 Stop 會清空 subagent 槽")
    func stopClearsSubSlot() {
        var s = merge(payload("PreToolUse", tool: "Bash"), into: nil)
        s = merge(payload("PostToolUse", tool: "Write", agent: "sub1"), into: s)
        #expect(s.subActivity == .working)

        s = merge(payload("Stop"), into: s)
        #expect(s.mainActivity == .done)
        #expect(s.subActivity == nil, "該輪的 subagent 都已結束")
        #expect(s.subTool == nil)
        // S2-5：從屬槽清空 ≠ 整體燈號已經 done —— sub1 還沒送 SubagentStop，
        // 依然「outstanding」（T23 A），effectiveActivity 必須反映這件事。
        #expect(s.effectiveActivity == .working, "sub1 未回報 SubagentStop，燈必須維持 working（T23 A）")
        s = merge(payload("SubagentStop", agent: "sub1"), into: s, at: t0.addingTimeInterval(1))
        #expect(s.effectiveActivity == .done, "sub1 回報完畢，燈才回到 done")
    }

    // ---- §2.5.1：主 agent 靜止後必須忽略 subagent 事件 ----

    @Test("Stop 之後 2.6s 抵達的內部 SubagentStop 不得把 done 變成 working")
    func internalSubagentStopAfterStopIsIgnored() {
        var s = merge(payload("Stop"), into: nil)
        #expect(s.mainActivity == .done)

        // 實測時序：agent_type 空字串的內部 subagent，Stop 後 +2.58s
        let internalSub = HookPayload(json: [
            "hook_event_name": "SubagentStop", "session_id": "s1",
            "agent_id": "a8c360a1fe475f199", "agent_type": "",
        ])!
        s = merge(internalSub, into: s, at: t0.addingTimeInterval(2.58))

        #expect(s.mainActivity == .done)
        #expect(s.subActivity == nil, "主 agent 靜止 → 不得寫 sub 槽")
        #expect(s.effectiveActivity == .done, "綠燈必須維持綠燈（S2-5：呼叫真正的 effectiveActivity）")
        #expect(s.writtenAt == t0.addingTimeInterval(2.58), "但時戳仍要更新")
    }

    @Test("StopFailure 之後的 SubagentStop 不得把 error 變成 working")
    func subagentStopAfterStopFailureIsIgnored() {
        var s = merge(payload("StopFailure"), into: nil)
        s = merge(payload("SubagentStop", agent: "a1"), into: s, at: t0.addingTimeInterval(3))
        #expect(s.mainActivity == .error)
        #expect(s.subActivity == nil)
        #expect(s.effectiveActivity == .error, "S2-5：聚合結果不能被忽略的 subagent 事件動搖")
    }

    @Test("PermissionRequest 之後的 subagent 事件不得寫 sub 槽")
    func subagentIgnoredWhileWaiting() {
        var s = merge(payload("PermissionRequest", tool: "Bash"), into: nil)
        s = merge(payload("PostToolUse", tool: "Write", agent: "a1"),
                  into: s, at: t0.addingTimeInterval(0.02))
        #expect(s.mainActivity == .waiting)
        #expect(s.subActivity == nil, "比單靠 max 更直接地保護 waiting")
        #expect(s.effectiveActivity == .waiting, "S2-5：聚合結果不能被忽略的 subagent 事件動搖")
    }

    @Test("主 agent 仍在 working 時，subagent 事件正常寫入 sub 槽")
    func subagentRecordedWhileWorking() {
        var s = merge(payload("PreToolUse", tool: "Bash"), into: nil)
        s = merge(payload("PostToolUse", tool: "Grep", agent: "a1", agentType: "Explore"), into: s)
        #expect(s.subActivity == .working)
        #expect(s.subTool == "Grep")
        #expect(s.subAgentType == "Explore")
    }

    @Test("agent_type 空字串的 subagent 不計入 subagents")
    func internalSubagentNotCounted() {
        let start = HookPayload(json: [
            "hook_event_name": "SubagentStart", "session_id": "s1",
            "agent_id": "a1", "agent_type": "",
        ])!
        let s = merge(start, into: nil)
        #expect(s.subagents.isEmpty, "不得出現空字串鍵")
    }

    /// **系統性的欄位帶過來測試。**
    ///
    /// `merge` 用 `?? s.field` 或 `if let ... { s.field = ... }` 把 14 個欄位帶過來，
    /// 但原本只有 `model` 有專門的帶過來測試。其餘 13 個若哪天被寫成直接覆寫
    /// （`s.cwd = p.cwd`），一個不帶 `cwd` 的事件就會把它清成 nil，而沒有任何測試會紅。
    ///
    /// 這個測試先用一連串事件把每個「來自 payload」的欄位都填上非 nil 值，
    /// 斷言確實都填上了（否則後面就是 nil == nil，證明不了任何事），
    /// 再送一個什麼都不帶的最小事件，斷言全部存活。
    @Test("後續事件不得清掉先前累積的欄位")
    func fieldsCarryForward() {
        func p(_ json: [String: Any]) -> HookPayload {
            HookPayload(json: json.merging(["session_id": "s1"]) { a, _ in a })!
        }
        var s = merge(p(["hook_event_name": "SessionStart", "cwd": "/x/proj",
                         "source": "startup", "model": "claude-opus-5[1m]"]), into: nil)
        s = merge(p(["hook_event_name": "UserPromptSubmit",
                     "permission_mode": "default", "effort": ["level": "xhigh"]]), into: s)
        s = merge(p(["hook_event_name": "PostToolUse", "tool_name": "Bash",
                     "tool_input": ["description": "下載檔案"], "duration_ms": 1234]), into: s)
        s = merge(p(["hook_event_name": "Notification",
                     "notification_type": "idle_prompt", "message": "等你輸入"]), into: s)

        // 先證明測試資料真的填上了 —— 否則下面是 nil == nil，什麼都沒驗到
        #expect(s.cwd != nil && s.source != nil && s.model != nil
                && s.permissionMode != nil && s.effort != nil && s.mainTool != nil
                && s.toolDescription != nil && s.toolDurationMs != nil
                && s.notificationType != nil && s.notificationMessage != nil,
                "setup 必須把每個欄位都填上非 nil")

        let before = s
        // 一個什麼都不帶的最小事件
        s = merge(p(["hook_event_name": "PostToolBatch"]), into: s,
                  at: t0.addingTimeInterval(60))

        #expect(s.cwd == before.cwd)
        #expect(s.source == before.source)
        #expect(s.model == before.model)
        #expect(s.permissionMode == before.permissionMode)
        #expect(s.effort == before.effort)
        #expect(s.mainTool == before.mainTool)
        #expect(s.toolDescription == before.toolDescription)
        #expect(s.toolDurationMs == before.toolDurationMs)
        #expect(s.notificationType == before.notificationType)
        #expect(s.notificationMessage == before.notificationMessage)
        #expect(s.turnStartedAt == before.turnStartedAt)
        #expect(s.writtenAt == t0.addingTimeInterval(60), "只有時戳該變")
    }

    @Test("model 只由 SessionStart 提供，後續事件必須帶過來")
    func modelCarriedForward() {
        let start = HookPayload(json: [
            "hook_event_name": "SessionStart", "session_id": "s1",
            "source": "startup", "model": "claude-opus-5[1m]",
        ])!
        var s = merge(start, into: nil)
        #expect(s.model == "claude-opus-5[1m]")
        s = merge(payload("UserPromptSubmit"), into: s, at: t0.addingTimeInterval(5))
        #expect(s.model == "claude-opus-5[1m]", "PreToolUse 等事件不帶 model，不得被清掉")
    }

    @Test("主 agent 的 StopFailure 同樣清空 subagent 槽")
    func stopFailureClearsSubSlot() {
        var s = merge(payload("PostToolUse", tool: "Write", agent: "sub1"), into: nil)
        s = merge(payload("StopFailure"), into: s)
        #expect(s.mainActivity == .error)
        #expect(s.subActivity == nil)
    }

    // ---- 累積欄位 ----

    @Test("UserPromptSubmit 設定 turnStartedAt，後續事件沿用")
    func turnStartTracking() {
        var s = merge(payload("UserPromptSubmit"), into: nil)
        #expect(s.turnStartedAt == t0)

        s = merge(payload("PreToolUse", tool: "Bash"), into: s, at: t0.addingTimeInterval(30))
        #expect(s.turnStartedAt == t0, "同一輪內不得被重設")

        s = merge(payload("UserPromptSubmit"), into: s, at: t0.addingTimeInterval(90))
        #expect(s.turnStartedAt == t0.addingTimeInterval(90), "新一輪重設")
    }

    @Test("subagents 依 agent_type 累加，SubagentStart 才計數")
    func subagentCounting() {
        var s: SessionSnapshot? = nil
        s = merge(payload("SubagentStart", agent: "a1", agentType: "Explore"), into: s)
        s = merge(payload("SubagentStart", agent: "a2", agentType: "Explore"), into: s)
        s = merge(payload("SubagentStart", agent: "a3", agentType: "implementer"), into: s)
        #expect(s?.subagents == ["Explore": 2, "implementer": 1])

        // 一般 tool 事件不得重複計數
        s = merge(payload("PostToolUse", tool: "Write", agent: "a1", agentType: "Explore"), into: s)
        #expect(s?.subagents == ["Explore": 2, "implementer": 1])
    }

    @Test("使用者 Ctrl+C 中斷不計入 toolFailures —— 那是使用者的動作")
    func interruptIsNotAFailure() {
        let interrupted = HookPayload(json: [
            "hook_event_name": "PostToolUseFailure", "session_id": "s1",
            "tool_name": "Bash", "is_interrupt": true,
            "error": "Interrupted by user",
        ])!
        var s = merge(interrupted, into: nil)
        s = merge(interrupted, into: s)
        #expect(s.toolFailures == 0, "中斷兩次仍是 0 次失敗")
        #expect(s.mainActivity == .working)

        let real = HookPayload(json: [
            "hook_event_name": "PostToolUseFailure", "session_id": "s1",
            "tool_name": "Read", "is_interrupt": false,
            "error": "File does not exist",
        ])!
        s = merge(real, into: s)
        #expect(s.toolFailures == 1, "真正的失敗才計入")
        #expect(s.toolError == "File does not exist")
    }

    @Test("toolFailures 累加，新一輪歸零")
    func toolFailureCounting() {
        var s: SessionSnapshot? = nil
        for _ in 0..<3 { s = merge(payload("PostToolUseFailure", tool: "Bash"), into: s) }
        #expect(s?.toolFailures == 3)
        #expect(s?.mainActivity == .working, "tool 失敗不改變 activity")

        s = merge(payload("UserPromptSubmit"), into: s, at: t0.addingTimeInterval(60))
        #expect(s?.toolFailures == 0, "新一輪重新計算")
    }

    // ---- 終止與復活 ----

    @Test("SessionEnd 標記 terminated 並保留最後的 activity")
    func sessionEndMarksTerminated() {
        var s = merge(payload("Stop"), into: nil)
        s = merge(payload("SessionEnd"), into: s)
        #expect(s.terminated)
        #expect(s.mainActivity == .done, "終止不得抹掉未確認的結果")
    }

    @Test("SessionStart 會清除 terminated（resume 情境）")
    func sessionStartClearsTerminated() {
        var s = merge(payload("SessionEnd"), into: nil)
        #expect(s.terminated)
        s = merge(payload("SessionStart"), into: s)
        #expect(!s.terminated)
        #expect(s.mainActivity == .idle)
    }

    @Test("noChange 事件只更新 writtenAt，不動 activity")
    func noChangePreservesActivity() {
        var s = merge(payload("PermissionRequest", tool: "Bash"), into: nil)
        s = merge(payload("Notification", notif: "auth_success"),
                  into: s, at: t0.addingTimeInterval(5))
        #expect(s.mainActivity == .waiting, "auth_success 不得改變 activity")
        #expect(s.writtenAt == t0.addingTimeInterval(5), "但時戳要更新")
    }

    @Test("未知 event 也只更新 writtenAt")
    func unknownEventPreservesActivity() {
        var s = merge(payload("PermissionRequest"), into: nil)
        s = merge(payload("FutureEvent2027"), into: s, at: t0.addingTimeInterval(3))
        #expect(s.mainActivity == .waiting)
        #expect(s.writtenAt == t0.addingTimeInterval(3))
    }

}
