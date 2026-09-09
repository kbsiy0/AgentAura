import Foundation

/// 把一個 hook event 併進既有狀態。`aura-hook` 與測試共用同一份規則。
public enum MergeRules {

    /// 落檔時保留的助理輸出長度上限。面板只用得到開頭幾十個字。
    static let storedMessageLimit = 500


    public static func merge(_ p: HookPayload,
                             into existing: SessionSnapshot?,
                             pid: Int32?,
                             pidStartedAt: Int64?,
                             now: Date) -> SessionSnapshot {
        var s = existing ?? SessionSnapshot(sessionID: p.sessionID)

        s.hookEventName = p.hookEventName
        s.writtenAt     = now
        s.pid           = pid ?? s.pid
        s.pidStartedAt  = pidStartedAt ?? s.pidStartedAt
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
                // §2.5.1 —— 主 agent 靜止時完全忽略 subagent 事件。
                // 實測：Claude Code 的內部 subagent（agent_type 空字串、只送
                // SubagentStop）會在主 agent Stop 之後 2.6s ~ 184s 才抵達。
                // 若寫進 sub 槽，max(done, working) = working，綠燈變藍燈且回不去。
                guard !s.mainActivity.isQuiescent else { break }
                s.subActivity  = a
                s.subTool      = p.toolName ?? s.subTool
                s.subAgentType = p.agentType ?? s.subAgentType
            } else {
                s.mainActivity = a
                if let t = p.toolName { s.mainTool = t }
                if p.hookEventName == "SessionStart" { s.terminated = false }
                // 一輪結束 → 該輪的 subagent 都已結束，清空從屬槽。
                if a == .done || a == .error { clearSubSlot(&s) }
            }
        case .sessionEnded:
            s.terminated = true            // 刻意保留 mainActivity：未確認的結果不得被抹掉
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
}
