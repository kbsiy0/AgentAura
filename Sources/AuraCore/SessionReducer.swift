import Foundation

public enum SessionReducer {

    public static func state(from s: SessionSnapshot,
                             liveness probe: LivenessProbing) -> SessionState {
        SessionState(
            id: s.sessionID,
            projectName: projectName(fromPath: s.cwd),
            permissionMode: s.permissionMode,
            effort: s.effort,
            model: s.model,
            agent: Agent(stored: s.agent),
            activity: s.effectiveActivity,
            mainActivity: s.mainActivity,
            subActivity: s.subActivity,
            currentTool: s.mainTool,
            subagentTool: subagentLabel(type: s.subAgentType, tool: s.subTool),
            toolDurationMs: s.toolDurationMs,
            turnStartedAt: s.turnStartedAt,
            subagents: s.subagents,
            toolFailures: s.toolFailures,
            lastMessage: s.lastMessage,
            errorType: s.mainActivity == .error ? s.reason : nil,
            toolError: s.toolError,
            toolDescription: s.toolDescription,
            notificationMessage: s.notificationMessage,
            liveness: Self.resolveLiveness(of: s, probe: probe),
            updatedAt: s.writtenAt
        )
    }

    /// 刻意不叫 `liveness` —— 那會被 `state(from:liveness:)` 的同名參數遮蔽。
    static func resolveLiveness(of s: SessionSnapshot, probe: LivenessProbing) -> Liveness {
        guard !s.terminated,
              let pid = s.pid, let started = s.pidStartedAt,
              probe.isAlive(pid: pid, startedAt: started)
        else { return .ended }
        return .alive(pid: pid)
    }

    static func projectName(fromPath path: String?) -> String {
        guard let path, !path.isEmpty else { return "(unknown)" }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? "(root)" : name
    }

    static func subagentLabel(type: String?, tool: String?) -> String? {
        switch (type, tool) {
        case let (t?, u?): return "\(t) → \(u)"
        case let (t?, nil): return t
        case let (nil, u?): return u
        default: return nil
        }
    }
}
