import Foundation

public struct SessionState: Sendable, Equatable, Identifiable {
    public let id: String
    public let projectName: String
    public let permissionMode: String?
    public let effort: String?
    /// 模型名稱。只有 `SessionStart`（與 `PostModelSwitch` 的 `to_model`）提供，
    /// 由 `MergeRules` 帶過來。
    ///
    /// 註：早期版本因為誤判「payload 不帶 model」而移除過這個欄位，後來實測推翻。
    /// 補回時只補了 `HookPayload` 與 `SessionSnapshot`，忘了輸出端 —— 值存得到卻
    /// 傳不出去，面板拿不到。修一條資料流要走完 payload → 檔案 → state → UI 四段。
    public let model: String?
    /// 產生這個 session 的來源 agent（codex-support §4.1／§3）。`SessionReducer` 從
    /// `Agent(stored: snapshot.agent)` 解析，未知值／nil 落回 `.claude`（D-b）。
    ///
    /// **帶預設值 `.claude`**（同本檔 `toolDescription`／`notificationMessage` 的既有理由）：
    /// 這個 init 有 21 個既有呼叫點散在 `Tests/AgentAuraAppTests` 的視覺／像素測試裡
    /// （App 層，多半不歸這個 change 管），那些測試建構 `SessionState` 只是為了量版面，
    /// 不關心 agent 是誰；生產路徑（`SessionReducer.state(from:liveness:)`）才是真正
    /// 需要明確傳 `agent:` 的地方，見該檔案。
    public let agent: Agent
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
    /// `PermissionRequest` 的 `tool_input.description` —— 「在等你批准**什麼**」。
    ///
    /// 只有 tool 名不夠：「等你批准：Bash」看不出在等什麼，而那正是最需要資訊的一列。
    /// （`HookPayload` 的 doc-comment 逐字寫過這件事，但這個欄位當初只走完
    /// payload → 檔案兩段，沒進 state 也沒進 UI —— 跟 `model` 是同一個坑。）
    public let toolDescription: String?
    /// `Notification` 帶的訊息文字，waiting 那一列的補充說明。
    public let notificationMessage: String?
    public let liveness: Liveness
    public let updatedAt: Date

    // 刻意提供公開的 memberwise init：`public let` 欄位的自動合成 init 只到 internal，
    // 跨模組（未來的 UI target）建構不到值。`IconState` 同理自帶 public init。
    public init(id: String, projectName: String,
                permissionMode: String?, effort: String?, model: String?,
                agent: Agent = .claude,
                activity: Activity, mainActivity: Activity, subActivity: Activity?,
                currentTool: String?, subagentTool: String?, toolDurationMs: Int?,
                turnStartedAt: Date?, subagents: [String: Int], toolFailures: Int,
                lastMessage: String?, errorType: String?, toolError: String?,
                toolDescription: String? = nil, notificationMessage: String? = nil,
                liveness: Liveness, updatedAt: Date) {
        self.id = id
        self.projectName = projectName
        self.permissionMode = permissionMode
        self.effort = effort
        self.model = model
        self.agent = agent
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
        self.toolDescription = toolDescription
        self.notificationMessage = notificationMessage
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
