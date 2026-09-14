import Testing
import Foundation
@testable import AuraCore

/// **T23 review S1-1**：`.sessionEnded` 沒有清空 `outstandingSubagents`，後果比
/// 「燈卡在 working」嚴重得多——一個**已經真的結束**的 session 會從面板與聚合
/// 燈裡整筆消失，不是燈色錯。
///
/// 成因：`SessionRegistry.visible`（`SessionRegistry.swift`）對已結束
/// （`liveness == .ended`）的 session 只留「有結果可看」的
/// （`activity == .done || .error`，見 §2.4.1）。如果 `outstandingSubagents`
/// 還留著一個從沒送 `SubagentStop` 的具名 subagent（例如整個行程被 `SessionEnd`
/// 收掉、它自己再也不會回報了），`effectiveActivity` 會被它的 `.working` 拖著跑，
/// 既不是 `.done` 也不是 `.error`——`isResult` 判 false，這個已經真正結束的
/// session 就從 `visible` 消失，而且救不回來：沒有下一個 hook 事件會再幫它寫檔。
///
/// 這條測試刻意走完整條管線（`MergeRules.merge` → `SessionReducer.state` →
/// `SessionRegistry.upsert`），不是只斷言 `effectiveActivity`——bug 的可見結果
/// 在 `SessionRegistry.visible` 那一層，斷言要釘在使用者真的會看到的地方。
@Suite("T23 review S1-1：SessionEnd 必須清空 outstandingSubagents，否則已結束 session 從面板消失")
struct SubagentSessionEndVisibilityTests {

    static func merge(_ p: HookPayload, into s: SessionSnapshot?) -> SessionSnapshot {
        MergeRules.merge(p, into: s, pid: 4242, pidStartedAt: 111, now: .distantPast)
    }

    @Test("已修：具名 subagent 沒送 SubagentStop 就 SessionEnd，該 session 仍留在 visible 裡")
    func sessionEndClearsOutstandingSubagentsSoEndedSessionStaysVisible() throws {
        var s = Self.merge(try #require(HookPayload(json: [
            "hook_event_name": "Stop", "session_id": "s1",
        ])), into: nil)
        #expect(s.mainActivity == .done)

        // 具名 subagent 還在跑，主 agent 已經講完話——這正是 T23 A 要修的情境。
        s = Self.merge(try #require(HookPayload(json: [
            "hook_event_name": "PostToolUse", "session_id": "s1",
            "agent_id": "a1", "agent_type": "implementer", "tool_name": "Bash",
        ])), into: s)
        #expect(s.outstandingSubagents == ["a1": .working])
        #expect(s.effectiveActivity == .working, "修好 A 之後，這裡本來就該是 working")

        // 整個行程被收掉（例如使用者關掉 terminal）——這個具名 subagent 再也
        // 不會送出它自己的 SubagentStop 了。
        s = Self.merge(try #require(HookPayload(json: [
            "hook_event_name": "SessionEnd", "session_id": "s1",
        ])), into: s)
        #expect(s.terminated)

        #expect(s.outstandingSubagents == nil, """
            **S1-1 已修**：行程都沒了，背景 subagent 不可能還在外面——SessionEnd
            必須清空這個集合，否則 effectiveActivity 永遠卡在 .working。
            """)
        #expect(s.effectiveActivity == .done, "主 agent 原本的結果（done）必須能重見天日")

        var registry = SessionRegistry()
        let state = SessionReducer.state(from: s, liveness: StubLiveness(table: [:]))
        #expect(state.liveness == .ended, "terminated 已設，liveness 必須是 ended")
        registry.upsert(state)

        #expect(registry.visible.map(\.id) == ["s1"], """
            **這才是使用者真的會看到的層級**：已結束、有真正結果（done）的 session
            必須留在 visible 裡（§2.4.1 的核心價值——整夜跑 pipeline，早上回來看得到）。
            修好之前它會從這裡直接消失，不是燈色錯，是整列不見。
            """)
    }
}
