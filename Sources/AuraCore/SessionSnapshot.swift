import Foundation

/// `~/.agentaura/sessions/<session_id>.json` 的內容。
///
/// 分成三類欄位：
/// 1. 每次事件**必定覆寫**的：`hookEventName`、`writtenAt`
///    （每個 payload 都一定帶這兩個值，所以沒有 carry-forward 的問題）
/// 1b. **carry-forward** 的：`cwd`、`permissionMode`、`effort`、`model`、`source`、
///    `reason`、`notificationType`、`toolDescription` … 這些用 `?? existing`
///    或 `if let`，不帶該欄位的事件會**保留舊值**。別改成直接賦值 ——
///    `fieldsCarryForward` 測試釘死的就是這件事。
/// 2. **分槽**欄位（`main*` / `sub*`）—— subagent 不得覆蓋主 agent，見 §2.5
/// 3. **累積**欄位（`turnStartedAt`、`subagents`、`toolFailures`）—— 由 `MergeRules` 帶過來
public struct SessionSnapshot: Codable, Sendable, Equatable {
    public var schema: Int = 1
    public var sessionID: String
    public var hookEventName: String = ""
    public var writtenAt: Date = .distantPast

    public var pid: Int32?
    public var pidStartedAt: Int64?

    public var cwd: String?
    public var permissionMode: String?
    public var effort: String?
    public var model: String?
    public var source: String?
    public var reason: String?

    public var mainActivity: Activity = .idle
    public var mainTool: String?
    public var subActivity: Activity?
    public var subTool: String?
    public var subAgentType: String?

    public var notificationType: String?
    public var notificationMessage: String?
    public var lastMessage: String?
    public var toolDescription: String?
    /// 最後一次 tool 失敗的訊息（`PostToolUseFailure` 的 `error`）。
    public var toolError: String?
    public var toolDurationMs: Int?

    public var turnStartedAt: Date?
    public var subagents: [String: Int] = [:]
    public var toolFailures: Int = 0
    public var terminated: Bool = false

    public init(sessionID: String) { self.sessionID = sessionID }

    /// 取兩槽的優先序最大值 —— `waiting`(3) > `working`(2)，故 subagent 蓋不掉 waiting。
    public var effectiveActivity: Activity { max(mainActivity, subActivity ?? .idle) }

    enum CodingKeys: String, CodingKey {
        case schema
        case sessionID       = "session_id"
        case hookEventName   = "hook_event_name"
        case writtenAt       = "written_at"
        case pid
        case pidStartedAt    = "pid_started_at"
        case cwd
        case permissionMode  = "permission_mode"
        case effort, model, source, reason
        case mainActivity    = "main_activity"
        case mainTool        = "main_tool"
        case subActivity     = "sub_activity"
        case subTool         = "sub_tool"
        case subAgentType    = "sub_agent_type"
        case notificationType    = "notification_type"
        case notificationMessage = "notification_message"
        case lastMessage         = "last_message"
        case toolDescription     = "tool_description"
        case toolError           = "tool_error"
        case toolDurationMs      = "tool_duration_ms"
        case turnStartedAt   = "turn_started_at"
        case subagents
        case toolFailures    = "tool_failures"
        case terminated
    }
}
