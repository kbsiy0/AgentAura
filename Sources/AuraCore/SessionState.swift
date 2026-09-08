import Foundation

public struct SessionState: Sendable, Equatable, Identifiable {
    public let id: String
    public let projectName: String
    public let projectPath: String?
    public let permissionMode: String?
    public let effort: String?
    /// 模型名稱。只有 `SessionStart`（與 `PostModelSwitch` 的 `to_model`）提供，
    /// 由 `MergeRules` 帶過來。
    ///
    /// 註：早期版本因為誤判「payload 不帶 model」而移除過這個欄位，後來實測推翻。
    /// 補回時只補了 `HookPayload` 與 `SessionSnapshot`，忘了輸出端 —— 值存得到卻
    /// 傳不出去，面板拿不到。修一條資料流要走完 payload → 檔案 → state → UI 四段。
    public let model: String?
    public let activity: Activity
    public let mainActivity: Activity
    public let subActivity: Activity?
    public let currentTool: String?
    public let subagentTool: String?
    public let toolDurationMs: Int?
    public let turnStartedAt: Date?
    public let subagents: [String: Int]
    public let toolFailures: Int
    public let lastMessage: String?
    public let errorType: String?
    /// 最後一次真正的 tool 失敗訊息（使用者中斷不算，見 `MergeRules`）。
    public let toolError: String?
    public let liveness: Liveness
    public let updatedAt: Date

    // 刻意提供公開的 memberwise init：`public let` 欄位的自動合成 init 只到 internal，
    // 跨模組（未來的 UI target）建構不到值。`IconState` 同理自帶 public init。
    public init(id: String, projectName: String, projectPath: String?,
                permissionMode: String?, effort: String?, model: String?,
                activity: Activity, mainActivity: Activity, subActivity: Activity?,
                currentTool: String?, subagentTool: String?, toolDurationMs: Int?,
                turnStartedAt: Date?, subagents: [String: Int], toolFailures: Int,
                lastMessage: String?, errorType: String?, toolError: String?,
                liveness: Liveness, updatedAt: Date) {
        self.id = id
        self.projectName = projectName
        self.projectPath = projectPath
        self.permissionMode = permissionMode
        self.effort = effort
        self.model = model
        self.activity = activity
        self.mainActivity = mainActivity
        self.subActivity = subActivity
        self.currentTool = currentTool
        self.subagentTool = subagentTool
        self.toolDurationMs = toolDurationMs
        self.turnStartedAt = turnStartedAt
        self.subagents = subagents
        self.toolFailures = toolFailures
        self.lastMessage = lastMessage
        self.errorType = errorType
        self.toolError = toolError
        self.liveness = liveness
        self.updatedAt = updatedAt
    }
}

// 註：刻意不提供 `SessionState.isQuiescent`。
// Ruling 10 之後 `SessionRegistry.visible` 改用明確的 `.done || .error`
// （`waiting` 不算「結果」），使 `SessionState` 層級的 isQuiescent 沒有生產消費者，
// 且會與 `Activity.isQuiescent` 邏輯重複。需要時寫 `state.activity.isQuiescent`。

public struct IconState: Sendable, Equatable {
    public let activity: Activity
    public let counts: [Activity: Int]
    public let liveCount: Int

    public init(activity: Activity, counts: [Activity: Int], liveCount: Int) {
        self.activity = activity; self.counts = counts; self.liveCount = liveCount
    }

    /// 「需要你」的定義：error + waiting。
    /// `done` 不計入 —— 它是「你可以去看了」，不是「你被擋著」。
    public var attentionCount: Int {
        (counts[.error] ?? 0) + (counts[.waiting] ?? 0)
    }

    public static let empty = IconState(activity: .idle, counts: [:], liveCount: 0)
}
