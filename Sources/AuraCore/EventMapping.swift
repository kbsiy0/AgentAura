/// 一個 hook event 對 session 狀態的效果。
public enum EventEffect: Equatable, Sendable {
    /// 設定 activity。
    case setActivity(Activity)
    /// 不改變 activity（未知 event、雜訊 notification）—— 只更新時戳。
    case noChange
    /// session 已終止。
    case sessionEnded
}

public enum EventMapping {

    /// 本模組明確處理的 event —— **`plugin/hooks/hooks.json` 必須註冊且僅註冊這些**。
    ///
    /// **⚠️ 加一個 event 進來不是免費的，是相容性決定。** 2026-09-15 實機事故：
    /// `PostModelSwitch` 在開發機（Claude Code 2.1.271）合法、`claude plugin validate
    /// --strict` 全綠，但同事的版本不認得它——**那一個鍵讓整份 `hooks.json` 解析失敗**，
    /// AgentAura 在那台機器上完全不運作，而且錯誤只在 `/plugin` 裡看得到。
    /// 本機 validator 對未知 event 只給 warning 說「entry ignored at runtime」，
    /// **那個寬容不能外推到別人的 runtime**。
    /// 所以：只註冊有把握長期穩定的核心 event；新增一個之前先問「沒有它會怎樣」，
    /// 答案若是「少一個錦上添花的欄位」，就不值得拿整個產品的可用性去換。
    ///
    /// 跨層一致性 gate（Task 13）從這個集合推導，不用手維護第二份清單。
    /// 手維護的清單會 drift：本專案已實際發生過 —— `Elicitation`（映射到 `waiting`，
    /// 代表「MCP server 在等你輸入」）有映射卻沒註冊，那個狀態永遠收不到，
    /// 而單元測試照樣全綠。
    public static let handledEvents: Set<String> = [
        "SessionStart", "UserPromptSubmit",
        "PreToolUse", "PostToolUse", "PostToolUseFailure", "PostToolBatch",
        "SubagentStart", "SubagentStop",
        "PreCompact", "PostCompact",
        "PermissionRequest", "PermissionDenied",
        "Elicitation", "ElicitationResult",
        "Notification",
        "Stop", "StopFailure", "SessionEnd",
    ]

    /// `handledEvents` 中刻意不改變 activity 的 event（目前是空集合）。
    ///
    /// **`PostModelSwitch` 曾經在這裡，2026-09-15 移除**——它帶 `to_model`，讓使用者中途
    /// `/model` 換模型後面板不顯示舊模型。但實機回報：**有些 Claude Code 版本不認得這個
    /// event，而一個不認得的鍵會讓整份 `hooks.json` 解析失敗**（不是忽略那一條），
    /// 於是 AgentAura 在那台機器上完全不運作。詳見 `handledEvents` 的相容性說明。
    /// 型別留著（不是直接砍掉常數）：`PluginWiringTests` 的跨層 gate 用它區分
    /// 「刻意註冊但不改 activity」與「漏了映射」，集合空不代表這個概念消失。
    public static let registeredButNoActivityChange: Set<String> = []

    /// hook event（必要時加上 `notification_type`）→ 效果。
    ///
    /// 設計不變量：`waiting` / `done` / `error` 皆為**靜止態** —— 在使用者行動前
    /// 不會有新事件覆寫它們。這是「單檔覆寫、最後寫的贏」不會弄丟資訊的前提。
    public static func effect(forEvent event: String,
                              notificationType: String? = nil) -> EventEffect {
        switch event {
        case "SessionStart":
            return .setActivity(.idle)

        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
             "PostToolBatch", "SubagentStart", "SubagentStop",
             "PreCompact", "PostCompact", "PermissionDenied", "ElicitationResult":
            // PostToolUseFailure 刻意映射到 working：tool 中途失敗是 agent 工作的
            // 正常組成（grep 沒命中、測試紅燈），不該把燈變紅。
            return .setActivity(.working)

        case "PermissionRequest", "Elicitation":
            return .setActivity(.waiting)

        case "Stop":
            return .setActivity(.done)

        case "StopFailure":
            return .setActivity(.error)

        case "SessionEnd":
            return .sessionEnded

        case "Notification":
            return notificationEffect(notificationType)

        default:
            // 上游新增 event 時必須靜默忽略，不得改變 activity 也不得爆掉。
            return .noChange
        }
    }

    /// `Notification` 中代表「需要使用者」的型別 —— **`hooks.json` 的 matcher
    /// 必須等於這個集合**（加上 `agent_completed`，它是 `done` 不是 waiting）。
    ///
    /// 與 `handledEvents` 同理：跨層 gate 從生產碼推導，不留第二份手寫清單。
    ///
    /// **`idle_prompt` 刻意不在這裡**（2026-09-09 實測修正，spec §2.2.1）：它在一輪結束
    /// 60 秒後必送，語意是「我講完了、你還沒講」——那是 `done` 的延續，不是被擋住。
    /// 第一版把它歸 waiting，結果每個講完話的 session 60 秒後都亮橘，R4「動＝需要你」失效。
    /// `IdlePromptTests` 釘住這條；把它加回來 gate 會紅、matcher gate 也會要求 hooks.json 跟著改。
    public static let notificationTypesNeedingUser: Set<String> = [
        "permission_prompt", "agent_needs_input",
        "elicitation_dialog", "elicitation_url_dialog",
    ]

    /// `Notification` 中代表「有結果可看」的型別。
    public static let notificationTypesMeaningDone: Set<String> = [
        "agent_completed",
    ]

    /// `Notification` 中**已知且刻意**不改變 activity 的型別（spec §2.2.1 的「不改變」列）。
    ///
    /// 與 `registeredButNoActivityChange` 同一個角色：讓「刻意忽略」與「落到 default 的未知型別」
    /// 在測試裡分得開 —— 真實 fixture 的回歸測試對前者放行、對後者變紅。
    /// `idle_prompt` 在此的理由見 `notificationTypesNeedingUser` 的說明。
    public static let notificationTypesDeliberatelyIgnored: Set<String> = [
        "idle_prompt",
        "auth_success", "elicitation_complete", "elicitation_response",
        "quota_auto_resume_fired", "quota_auto_resume_stale", "quota_auto_resume_disabled",
    ]

    /// `hooks.json` 的 `Notification` matcher 應涵蓋的全部型別。
    public static var notificationMatcherTypes: Set<String> {
        notificationTypesNeedingUser.union(notificationTypesMeaningDone)
    }

    /// `Notification` 的型別分流（§2.2.1）。
    ///
    /// 未知型別一律 `.noChange`。理由：未知空間裡佔多數的是雜訊（auth、quota），
    /// 誤報會讓 icon 無故亮橘；而「有人在等你」已由獨立的 `PermissionRequest`
    /// event 直接覆蓋，不需要靠 `Notification` 兜底。
    static func notificationEffect(_ type: String?) -> EventEffect {
        guard let type else { return .noChange }
        if notificationTypesNeedingUser.contains(type) { return .setActivity(.waiting) }
        if notificationTypesMeaningDone.contains(type) { return .setActivity(.done) }
        return .noChange
    }
}
