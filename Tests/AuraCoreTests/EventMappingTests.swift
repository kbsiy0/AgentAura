import Testing
@testable import AuraCore

@Suite("event → activity 對照（§2.2）")
struct EventMappingTests {

    func effect(_ e: String, _ t: String? = nil) -> EventEffect {
        EventMapping.effect(forEvent: e, notificationType: t)
    }

    @Test("工作中的事件全部映射到 working")
    func workingEvents() {
        for e in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolBatch",
                  "SubagentStart", "SubagentStop", "PreCompact", "PostCompact",
                  "PermissionDenied", "ElicitationResult"] {
            #expect(effect(e) == .setActivity(.working), "\(e) 應為 working")
        }
    }

    @Test("PostToolUseFailure 是 working 而非 error（前一版的 bug）")
    func toolFailureIsNotError() {
        #expect(effect("PostToolUseFailure") == .setActivity(.working),
                "tool 中途失敗是 agent 工作的正常組成；紅色只保留給 StopFailure")
    }

    @Test("等待與終止事件")
    func waitingAndTerminal() {
        #expect(effect("SessionStart")      == .setActivity(.idle))
        #expect(effect("PermissionRequest") == .setActivity(.waiting))
        #expect(effect("Elicitation")       == .setActivity(.waiting))
        #expect(effect("Stop")              == .setActivity(.done))
        #expect(effect("StopFailure")       == .setActivity(.error))
        #expect(effect("SessionEnd")        == .sessionEnded)
    }

    @Test("未知 event 不改變 activity（上游新增 event 不得爆掉）")
    func unknownEventIsNoChange() {
        #expect(effect("SomeFutureEventFromClaudeCode2027") == .noChange)
        #expect(effect("") == .noChange)
    }

    // ---- Notification 的 12 種型別（§2.2.1）----

    @Test("需要使用者的 notification 型別 → waiting", arguments: [
        "permission_prompt", "idle_prompt", "agent_needs_input",
        "elicitation_dialog", "elicitation_url_dialog",
    ])
    func notificationNeedsUser(_ type: String) {
        #expect(effect("Notification", type) == .setActivity(.waiting))
    }

    @Test("agent_completed 是 done 而不是 waiting")
    func agentCompletedIsDone() {
        #expect(effect("Notification", "agent_completed") == .setActivity(.done),
                "背景 agent 跑完應顯示 done，不該讓 icon 亮成「需要你」")
    }

    @Test("雜訊型別不改變 activity（不得無故亮橘燈）", arguments: [
        "auth_success", "elicitation_complete", "elicitation_response",
        "quota_auto_resume_fired", "quota_auto_resume_stale", "quota_auto_resume_disabled",
    ])
    func notificationNoise(_ type: String) {
        #expect(effect("Notification", type) == .noChange)
    }

    @Test("未知或缺失的 notification_type 不改變 activity")
    func notificationUnknown() {
        #expect(effect("Notification", "brand_new_type_2027") == .noChange)
        #expect(effect("Notification", nil) == .noChange)
        #expect(effect("Notification", "") == .noChange)
    }

    // ---- handledEvents 與 switch 必須一致（防兩者 drift）----

    @Test("handledEvents 裡除了刻意不改 activity 的，其餘都必須有映射")
    func handledEventsAllMapped() {
        for e in EventMapping.handledEvents
            where !EventMapping.registeredButNoActivityChange.contains(e) {
            let r = EventMapping.effect(forEvent: e,
                                        notificationType: e == "Notification" ? "idle_prompt" : nil)
            #expect(r != .noChange, "\(e) 在 handledEvents 裡卻落到 default")
        }
    }

    @Test("registeredButNoActivityChange 必須是 handledEvents 的子集")
    func noChangeSetIsSubset() {
        #expect(EventMapping.registeredButNoActivityChange
                    .isSubset(of: EventMapping.handledEvents))
    }

    @Test("PostModelSwitch 不改 activity 但仍在 handledEvents 裡（因為帶 to_model）")
    func postModelSwitchIsRegisteredButInert() {
        #expect(EventMapping.handledEvents.contains("PostModelSwitch"))
        #expect(EventMapping.effect(forEvent: "PostModelSwitch") == .noChange)
    }

    // ---- 真實 fixture 回歸：每一筆實測 event 都必須被明確處理 ----

    /// 對現實的回歸測試 —— **必須含 round2**。
    ///
    /// round1 + round1b 只有 6 種 event（`SessionStart`、`UserPromptSubmit`、
    /// `PreToolUse`、`PostToolUse`、`Stop`、`SessionEnd`），而這 6 種全都已被本檔
    /// 其他具名測試釘住，所以只載它們等於零增量保護。
    ///
    /// round2 多帶 5 種本測試否則完全碰不到的：`Notification`、`PermissionRequest`、
    /// `PostToolBatch`、`PostToolUseFailure`、`SubagentStop`。其中
    /// **`PostToolUseFailure` 與 `Notification` 正是兩個靠實測才修對的映射**
    /// （前者原本錯映射成 error、後者的未知型別 fallback 原本錯成 waiting），
    /// 也就是最該有現實回歸測試的兩個。覆蓋從 6 種提升到 11 種。
    @Test("三份 fixture 裡的每個真實 event 都不落到 noChange")
    func realEventsAreAllMapped() throws {
        let all = try Fixtures.rawEvents(named: "round1")
            + Fixtures.rawEvents(named: "round1b")
            + Fixtures.rawEvents(named: "round2")
        let kinds = Set(all.compactMap { $0["hook_event_name"] as? String })
        #expect(kinds.count >= 11, "三份 fixture 應涵蓋至少 11 種 event，實際 \(kinds.sorted())")
        for ev in all {
            let name = try #require(ev["hook_event_name"] as? String)
            let e = EventMapping.effect(forEvent: name,
                                       notificationType: ev["notification_type"] as? String)
            #expect(e != .noChange, "實測捕獲的 \(name) 竟然沒有對照規則")
        }
    }
}
