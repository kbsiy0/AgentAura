import Foundation

/// 把一個 hook event 併進既有狀態。`aura-hook` 與測試共用同一份規則。
public enum MergeRules {

    /// 落檔時保留的助理輸出長度上限。面板只用得到開頭幾十個字。
    static let storedMessageLimit = 500


    /// `agent` **不給預設值**（spec §4.1「5a」）：呼叫端必須明確表態這筆事件來自哪個
    /// agent，不能靜默落回 `.claude`——那會讓 Codex 的事件被誤標成 Claude 的。
    public static func merge(_ p: HookPayload,
                             into existing: SessionSnapshot?,
                             pid: Int32?,
                             pidStartedAt: Int64?,
                             agent: Agent,
                             now: Date) -> SessionSnapshot {
        var s = existing ?? SessionSnapshot(sessionID: p.sessionID)

        s.hookEventName = p.hookEventName
        s.writtenAt     = now
        s.pid           = pid ?? s.pid
        s.pidStartedAt  = pidStartedAt ?? s.pidStartedAt
        // carry-forward，比照 cwd／model：`.claude` 的 storedRawValue 是 nil，
        // 所以已經標成 codex 的 session 不會被後續不帶 agent 資訊的呼叫洗回 claude；
        // 新 session 起始值本來就是 nil，等同 claude（CX9）。
        s.agent          = agent.storedRawValue ?? s.agent
        s.cwd            = p.cwd ?? s.cwd
        s.permissionMode = p.permissionMode ?? s.permissionMode
        s.effort         = p.effortLevel ?? s.effort
        // model 只有 SessionStart 提供，必須帶過來（§2.1.1 第二輪校正）。
        s.model          = p.model ?? s.model
        if let src = p.source   { s.source = src }
        if let r   = p.reason   { s.reason = r }
        if let n   = p.notificationType { s.notificationType = n }
        if let nm  = p.notificationMessage { s.notificationMessage = nm }
        if let td  = p.toolDescription  { s.toolDescription = td }
        // **截斷後才落檔。** 這是助理輸出的原文，會躺在磁碟上；面板只用得到開頭
        // 幾十個字（`PanelViewModel.summarise` 截 80）。存全文只是把使用者的內容
        // 無謂地攤在檔案系統上，而且 1MB 的訊息實測是可能的。
        if let m   = p.lastMessage      { s.lastMessage = String(m.prefix(Self.storedMessageLimit)) }
        if let d   = p.toolDurationMs   { s.toolDurationMs = d }

        applyCounters(p, to: &s, now: now)

        switch p.effect {
        case .setActivity(let a):
            if p.isSubagent {
                // T23（審計 §6.1/§6.2）—— 具名 subagent 的第三個狀態來源，獨立於
                // 下面那條 quiescent guard：內部 subagent（agentType 為 nil）從不
                // 進來，它的遲到 SubagentStop 自然是 no-op，不必再靠猜主槽狀態。
                updateOutstandingSubagents(p, a, &s)

                // §2.5.1 —— 主 agent 靜止時忽略「從屬槽」的寫入（上面那行不受這條管）。
                // 實測：Claude Code 的內部 subagent（agent_type 空字串、只送
                // SubagentStop）會在主 agent Stop 之後 2.6s ~ 184s 才抵達。
                // 若寫進 sub 槽，max(done, working) = working，綠燈變藍燈且回不去。
                guard !s.mainActivity.isQuiescent else { break }
                if p.hookEventName == "SubagentStop" {
                    // T23（審計 §6.3）—— 對從屬槽而言這是「它結束了」，不是「還在
                    // 工作」：EventMapping 回傳 .working 是為了主槽（subagent 回來，
                    // 主 agent 繼續工作），套在從屬槽語意就反了，還會讓 subTool／
                    // subAgentType 的 carry-forward 殘留成它最後用過的 tool。
                    clearSubSlot(&s)
                } else {
                    s.subActivity  = a
                    s.subTool      = p.toolName ?? s.subTool
                    s.subAgentType = p.agentType ?? s.subAgentType
                }
            } else {
                s.mainActivity = a
                if let t = p.toolName { s.mainTool = t }
                if p.hookEventName == "SessionStart" { s.terminated = false }
                // 一輪結束 → 該輪的 subagent 都已結束，清空從屬槽。
                if a == .done || a == .error { clearSubSlot(&s) }
            }
        case .sessionEnded:
            s.terminated = true            // 刻意保留 mainActivity：未確認的結果不得被抹掉
            // T23 review S1-1 —— 行程都沒了，背景具名 subagent 不可能還在外面。
            // 不清的話，一個從沒送 SubagentStop 就被收掉的具名 subagent 會讓
            // effectiveActivity 卡在 .working，使這個已經真正結束的 session 在
            // SessionRegistry.visible 判「有結果可看」（done／error）時判不過，
            // 整筆從面板消失——不是燈色錯，是比「燈卡住」嚴重得多的後果。
            s.outstandingSubagents = nil
        case .noChange:
            break                          // 只更新了時戳
        }
        return s
    }

    static func applyCounters(_ p: HookPayload, to s: inout SessionSnapshot, now: Date) {
        if !p.isSubagent, p.hookEventName == "UserPromptSubmit" {
            s.turnStartedAt = now          // 新一輪：重設時戳與計數
            s.toolFailures  = 0
            s.subagents     = [:]
            // 保險：具名 subagent 崩潰而沒送 SubagentStop，集合會卡住不清——
            // 新一輪來了就清空，最多髒這一輪（審計 §7 風險評估）。
            s.outstandingSubagents = nil
        }
        // 使用者按 Ctrl+C 中斷不算失敗 —— 那是使用者的動作。
        // `is_interrupt` 與 `error` 同在 `PostToolUseFailure` 上（實測）。
        if p.hookEventName == "PostToolUseFailure", !p.isInterrupt { s.toolFailures += 1 }
        if let e = p.toolError { s.toolError = e }
        // agentType 已在 HookPayload 把空字串正規化為 nil，故內部 subagent 不計入。
        if p.hookEventName == "SubagentStart", let type = p.agentType {
            s.subagents[type, default: 0] += 1
        }
    }

    static func clearSubSlot(_ s: inout SessionSnapshot) {
        s.subActivity = nil
        s.subTool = nil
        s.subAgentType = nil
    }

    /// 更新「還在外面的具名 subagent」集合（T23，審計 §6.1）。
    ///
    /// 只認 `agentType` 非空的事件——`HookPayload` 已把內部 subagent 的空字串
    /// 正規化成 nil，所以這裡不需要另外判斷「是不是內部 subagent」。
    /// `SubagentStop` 從集合移除；其餘 subagent 事件 upsert 它自己的 activity
    /// （不是寫死 `.working`——背景 subagent 的 `PermissionRequest` 也要能讓
    /// 燈變橘，見審計 §6.2）。
    static func updateOutstandingSubagents(_ p: HookPayload, _ a: Activity, _ s: inout SessionSnapshot) {
        guard let id = p.agentID, p.agentType != nil else { return }
        if p.hookEventName == "SubagentStop" {
            s.outstandingSubagents?.removeValue(forKey: id)
        } else {
            s.outstandingSubagents = s.outstandingSubagents ?? [:]
            s.outstandingSubagents?[id] = a
        }
    }
}
