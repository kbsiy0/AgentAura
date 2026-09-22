import Foundation

/// codex-support T01 必辦⑤：程式合成的對抗式 hook payload（spec §6.1(1)），供 T03／T05
/// 的 `HookPayload`／`codexEvents` 相關測試共用。每個都是**真的能解析**的 JSON，
/// 只是缺欄位或欄位形狀刁鑽——供測試斷言既有解析器（或新的 Codex 分支）在這些形狀下
/// 仍不炸、仍給出保守的結果。
enum CodexAdversarialPayloads {
    /// 缺 `permission_mode`。
    static let missingPermissionMode = Data(#"""
        {"hook_event_name":"SessionStart","session_id":"01990001-0000-7000-8000-000000000001",
         "cwd":"/tmp/demo","model":"gpt-5.5","source":"startup"}
        """#.utf8)

    /// 缺 `model`（`SessionStart` 通常帶 `model`，這裡刻意不帶）。
    static let missingModel = Data(#"""
        {"hook_event_name":"SessionStart","session_id":"01990001-0000-7000-8000-000000000002",
         "cwd":"/tmp/demo","permission_mode":"bypassPermissions","source":"startup"}
        """#.utf8)

    /// `tool_response` 是一個 200 KB 的字串（F4：Codex 的 `tool_response` 是純字串）。
    static let toolResponse200KBString: Data = {
        let big = String(repeating: "x", count: 200_000)
        let obj: [String: Any] = [
            "hook_event_name": "PostToolUse",
            "session_id": "01990001-0000-7000-8000-000000000003",
            "cwd": "/tmp/demo", "model": "gpt-5.5", "permission_mode": "bypassPermissions",
            "tool_name": "Bash", "tool_input": ["command": "echo hi"],
            "tool_use_id": "call_1", "tool_response": big,
        ]
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }()

    /// `hook_event_name: "Interrupt"` **帶** `agent_id`——同名陷阱的對抗式輸入：
    /// `Interrupt` 事件與 `is_interrupt` 欄位是兩件事，這裡刻意讓兩個概念同時出現在
    /// 一筆 payload 上，逼測試把它們分開處理。
    static let interruptWithAgentID = Data(#"""
        {"hook_event_name":"Interrupt","session_id":"01990001-0000-7000-8000-000000000004",
         "cwd":"/tmp/demo","agent_id":"sub-1","agent_type":"implementer"}
        """#.utf8)

    /// `session_id` 是 UUIDv7（F2：Codex 的 `session_id`／`turn_id` 都是 UUIDv7，
    /// 與 Claude 的一般 UUID 不同版本；CX38 的「id 空間不交集」假設要有這種樣本可測）。
    static let sessionIDUUIDv7 = Data(#"""
        {"hook_event_name":"Stop","session_id":"01996a10-7c3e-7f2a-9b1c-0123456789ab",
         "cwd":"/tmp/demo","model":"gpt-5.5","permission_mode":"bypassPermissions",
         "stop_hook_active":false,"last_assistant_message":"OK"}
        """#.utf8)

    /// 全部五個，供「逐一都能安全解析」這類迴圈式斷言使用。
    static let all: [(name: String, data: Data)] = [
        ("missingPermissionMode", missingPermissionMode),
        ("missingModel", missingModel),
        ("toolResponse200KBString", toolResponse200KBString),
        ("interruptWithAgentID", interruptWithAgentID),
        ("sessionIDUUIDv7", sessionIDUUIDv7),
    ]
}
