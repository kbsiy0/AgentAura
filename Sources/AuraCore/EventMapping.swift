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
        "PostModelSwitch",
    ]

    /// `handledEvents` 中刻意不改變 activity 的 event。
    ///
    /// 它們仍必須註冊，因為帶了別的必要資訊：`PostModelSwitch` 帶 `to_model`
    /// （使用者中途 `/model` 換模型後，面板不得顯示舊模型）。
    public static let registeredButNoActivityChange: Set<String> = [
        "PostModelSwitch",
    ]

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
    public static let notificationTypesNeedingUser: Set<String> = [
        "permission_prompt", "idle_prompt", "agent_needs_input",
        "elicitation_dialog", "elicitation_url_dialog",
    ]

    /// `Notification` 中代表「有結果可看」的型別。
    public static let notificationTypesMeaningDone: Set<String> = [
        "agent_completed",
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
