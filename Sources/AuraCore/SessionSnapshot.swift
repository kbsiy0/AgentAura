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

    /// 在外面還沒回來的**具名** subagent（T23，審計 §6.1）。Key 是 `agent_id`
    /// （`subagents` 是依 agent **type** 計數，兩者用途不同，別搞混），value 是
    /// 它自己最後回報的 activity。
    ///
    /// 只有 `agentType` 非空的 subagent 事件會進來——內部 subagent（`agent_type`
    /// 空字串，`HookPayload` 已正規化成 nil）從不進集合，它的遲到 `SubagentStop`
    /// 天生就摸不到這個欄位，不需要另外用「主槽是否靜止」去猜。
    ///
    /// **必須是 Optional**（不是 `= [:]`）才能讓舊版狀態檔安全解碼：synthesized
    /// `Decodable` 對 Optional 屬性會用 `decodeIfPresent`，缺這個 key 時自然變 nil；
    /// 换成非 Optional 預設值不會改變這件事——synthesis 仍會要求 key 存在，
    /// 缺了就整包解碼失敗（`decodesLegacySnapshotMissingOutstandingSubagentsField`）。
    /// nil／缺這個 key 視同空集合。
    public var outstandingSubagents: [String: Activity]? = nil

    public init(sessionID: String) { self.sessionID = sessionID }

    /// 取三個輸入的優先序最大值 —— `waiting`(3) > `working`(2)，故 subagent 蓋不掉 waiting。
    /// 第三個輸入是 `outstandingSubagents`（T23，審計 §6.1/§6.2）：背景還沒回來的
    /// 具名 subagent，即使主槽已經靜止（done／error），它們自己的 activity 仍然算數。
    public var effectiveActivity: Activity {
        let outstanding = outstandingSubagents?.values.max() ?? .idle
        return max(max(mainActivity, subActivity ?? .idle), outstanding)
    }

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
        case outstandingSubagents = "outstanding_subagents"
    }
}
