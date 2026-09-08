import Foundation

/// Claude Code 送進 hook stdin 的 payload。
///
/// 刻意用字典讀取而非 `Codable`：上游 schema 會變（實測已發現 4 處與文件不符），
/// 字典讀取對未知欄位、缺失欄位、改型欄位天生容忍；`Codable` 一個欄位型別對不上
/// 就整包解碼失敗。
public struct HookPayload: Sendable, Equatable {
    public let hookEventName: String
    public let sessionID: String
    public let cwd: String?
    public let permissionMode: String?
    public let effortLevel: String?
    public let source: String?
    public let reason: String?
    public let toolName: String?
    /// `tool_input.description` —— Claude Code 為 Bash 等 tool 產生的人可讀說明。
    /// 面板在 waiting 那一列要顯示「在等你批准什麼」，只有 `toolName` 不夠
    ///（「等待權限：Bash」看不出在等什麼，而那正是最需要資訊的一列）。
    public let toolDescription: String?
    public let toolDurationMs: Int?
    /// 只有 `SessionStart` 帶 `model`；`PostModelSwitch` 用 `to_model` 帶新模型。
    /// 少了後者，使用者中途 `/model` 換模型後面板會顯示過時的模型。
    public let model: String?
    public let notificationType: String?
    public let notificationMessage: String?
    public let lastMessage: String?
    public let agentID: String?
    /// 內部 subagent 的 `agent_type` 是**空字串**而非 `null` —— 正規化為 nil，
    /// 否則 `subagents` 會出現 `"": N` 這種無意義鍵，也會把內部記帳 agent 算成使用者工作（§2.5.1）。
    public let agentType: String?

    /// `agent_id` 非 nil 即為 subagent 的事件。主 agent 的事件此欄為 `null`。
    public var isSubagent: Bool { agentID != nil }

    public var effect: EventEffect {
        EventMapping.effect(forEvent: hookEventName, notificationType: notificationType)
    }

    public init?(json: [String: Any]) {
        guard let event = json["hook_event_name"] as? String, !event.isEmpty,
              let sid = Self.string(json["session_id"]), !sid.isEmpty
        else { return nil }

        hookEventName    = event
        sessionID        = sid
        cwd              = Self.string(json["cwd"])
        permissionMode   = Self.string(json["permission_mode"])
        effortLevel      = Self.effortLevel(json["effort"])
        source           = Self.string(json["source"])
        // 文件寫 end_reason，實測是 reason —— 兩者都讀。
        reason           = Self.string(json["reason"]) ?? Self.string(json["end_reason"])
        toolName         = Self.string(json["tool_name"])
        toolDescription  = Self.nonEmpty((json["tool_input"] as? [String: Any])?["description"])
        toolDurationMs   = json["duration_ms"] as? Int
        model            = Self.nonEmpty(json["model"]) ?? Self.nonEmpty(json["to_model"])
        notificationType = Self.nonEmpty(json["notification_type"])
        notificationMessage = Self.nonEmpty(json["message"])
        lastMessage      = Self.string(json["last_assistant_message"])
        agentID          = Self.nonEmpty(json["agent_id"])
        agentType        = Self.nonEmpty(json["agent_type"])
    }

    public init?(data: Data) {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any]
        else { return nil }
        self.init(json: dict)
    }

    /// 只接受真正的 String；`NSNull`、數字、容器都轉不成 String，自然回 nil。
    static func string(_ any: Any?) -> String? { any as? String }

    /// 同 `string`，但空字串也視為缺值。
    static func nonEmpty(_ any: Any?) -> String? {
        guard let s = any as? String, !s.isEmpty else { return nil }
        return s
    }

    /// `effort` 實測是 `{"level":"xhigh"}`，但也容忍字串形狀（防上游改格式）。
    static func effortLevel(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        if let d = any as? [String: Any] { return string(d["level"]) }
        return nil
    }
}
