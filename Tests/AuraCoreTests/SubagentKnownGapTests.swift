import Testing
import Foundation
@testable import AuraCore

/// **這個 suite 釘的是「今天的行為」，不是「正確的行為」。**
///
/// 2026-09-11 使用者實機回報「燈號是綠色或等待色，但畫面上其實沒有任何事在發生」。
/// 審計（`docs/2026-09-11-subagent-state-priority-audit.html`）找到五個成因，其中
/// A／B／C 三個是真的落差。使用者裁決 **(c)：先釘住現況、寫進 known gaps，phase 2
/// 收尾後再開一輪修邏輯**——所以這裡的斷言刻意寫成「今天會發生什麼」。
///
/// **給未來修這件事的人：** 這四條裡的後三條（`gapA_`／`gapB_`／`gapC_`）在修好之後
/// **一定會變紅，那是預期的**。請**改寫**它們成新契約（連同測試名裡的 `gap` 前綴一起拿掉），
/// 不要刪掉——刪掉就沒有人知道舊行為長什麼樣、也就沒有東西證明真的改過了。
/// 第一條 `measuredNamedSubagentPayloadShape` 是**平台實測契約**不是落差，修的時候不得放寬：
/// 整個提案（用 `agent_type` 分辨具名／內部、用 `agent_id` 把結束配回開始）就站在它上面。
///
/// 落差成因都在 `MergeRules.merge` 的這一行（§2.5.1）：
/// ```swift
/// guard !s.mainActivity.isQuiescent else { break }
/// ```
/// 它是用**內部** subagent 的證據寫出來的（`agent_type` 空字串、Stop 後 2.58s–186s 才到，
/// 見 `FixtureIntegrityTests.round2SubagentStopAfterStop`），卻套用在**所有** subagent 事件上。
@Suite("已知落差：主槽靜止之後的具名 subagent（審計 2026-09-11，裁決 (c) 暫不修）")
struct SubagentKnownGapTests {

    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    /// 從 round3 fixture 取真實 payload；`kind` 是 `hook_event_name`。
    static func measured(_ kind: String) throws -> HookPayload {
        let raw = try Fixtures.events(named: "round3-named-subagent", kind: kind)
        let first = try #require(raw.first, "round3 fixture 裡沒有 \(kind)")
        return try #require(HookPayload(json: first), "\(kind) 解析失敗")
    }

    static func merge(_ p: HookPayload, into s: SessionSnapshot?, after seconds: TimeInterval = 0) -> SessionSnapshot {
        MergeRules.merge(p, into: s, pid: 4242, pidStartedAt: 111,
                         now: t0.addingTimeInterval(seconds))
    }

    // MARK: - 平台實測契約（不是落差，修的時候不得放寬）

    /// **修法所需的區別在資料層成立。** 2026-09-11 21:30 用獨立探針 plugin
    /// （不碰 repo、不碰 `~/.claude/settings.json`）跑一個真的 `claude -p` session 派
    /// `general-purpose` subagent 抓到的三筆事件。
    ///
    /// 兩件事一起成立才撐得住提案：
    /// 1. 具名 subagent 的 `SubagentStart` 與 `SubagentStop` **都**帶非空 `agent_type`
    ///    → 分得出「具名」與「內部」（後者是空字串，見 `round2HasInternalSubagent`）。
    /// 2. 兩者帶**同一個** `agent_id` → 結束事件配得回開始事件，不必依賴 `agent_type`
    ///    出現在結束事件上，也不必數數。
    @Test("實測：具名 subagent 的 start／stop 都帶非空 agent_type，且 agent_id 相同")
    func measuredNamedSubagentPayloadShape() throws {
        let start = try Self.measured("SubagentStart")
        let stop = try Self.measured("SubagentStop")
        let mainStop = try Self.measured("Stop")

        #expect(start.isSubagent, "SubagentStart 必須帶 agent_id")
        #expect(stop.isSubagent, "SubagentStop 必須帶 agent_id")
        #expect(!mainStop.isSubagent, "主 agent 的 Stop 不帶 agent_id")

        #expect(start.agentType == "general-purpose")
        #expect(stop.agentType == "general-purpose",
                """
                具名 subagent 的 SubagentStop 也帶 agent_type —— 這是「具名 vs 內部」
                在資料層分得開的依據。內部 subagent 是空字串（HookPayload 正規化成 nil）。
                """)
        #expect(start.agentID == stop.agentID,
                "同一個 agent_id 貫穿 start 與 stop —— 未來用它把結束配回開始")
        #expect(start.sessionID == stop.sessionID && stop.sessionID == mainStop.sessionID,
                "subagent 與父 session 共用 session_id（覆蓋 bug 的根源，§2.5）")
    }

    // MARK: - 落差 A：主 agent 講完話之後，背景具名 subagent 還在跑

    /// **今天：燈是綠的（done），但工作其實還在背景跑。**
    ///
    /// 主 agent 送 `Stop` 之後，`clearSubSlot` 清空從屬槽、`isQuiescent` guard 讓之後
    /// 所有 subagent 事件都被丟掉——包含**具名**的。實測 `round1` 有一個 `implementer`
    /// subagent 在 42 秒內連送 14 個 tool 事件，那段期間主槽完全有可能已經 done。
    ///
    /// 修好之後這裡應該是 `.working`（背景還有具名 subagent 在外面）。
    @Test("落差 A：Stop 之後具名 subagent 的 tool 事件不改變燈號（今天停在 done）")
    func gapA_backgroundNamedSubagentCannotKeepLightWorking() throws {
        var s = Self.merge(try Self.measured("Stop"), into: nil)
        #expect(s.mainActivity == .done)

        // 真實形狀：帶 agent_id 與非空 agent_type 的 PostToolUse（取自 round1 的 implementer）。
        let namedTool = try #require(HookPayload(json: [
            "hook_event_name": "PostToolUse", "session_id": s.sessionID,
            "agent_id": "adad9c77b1e0f4a21", "agent_type": "implementer", "tool_name": "Bash",
        ]))
        #expect(namedTool.isSubagent && namedTool.agentType == "implementer")

        s = Self.merge(namedTool, into: s, after: 8)

        #expect(s.subActivity == nil, "guard 丟掉了它，從屬槽沒被寫")
        #expect(s.effectiveActivity == .done, """
            **已知落差 A**：背景具名 subagent 還在跑，燈卻說「有結果可看」。
            修好之後這一行應該是 .working，屆時請改寫這條測試而不是刪掉它。
            """)
        #expect(s.writtenAt == Self.t0.addingTimeInterval(8), "但時戳照樣更新（既有行為）")
    }

    // MARK: - 落差 B：背景具名 subagent 在等使用者決策

    /// **今天：燈是綠的，實際上有人卡著等你批准。**
    ///
    /// 這是既有 invariant「`waiting` 不得進入已結束未確認的尾巴」（不該橘卻橘）的**鏡像**：
    /// 該橘卻不橘。同一條 guard 造成的，只是方向相反。
    ///
    /// **這個組合沒有實測樣本**——探針那次沒有撞到需要批准的 tool。`agent_id` 的形狀取自
    /// 實測（round3），事件名取自 `EventMapping.handledEvents`。等到真的量到之前，這條
    /// 測的是「我們的規則怎麼處理這個形狀」，不是「平台一定會送這個形狀」。
    @Test("落差 B：Stop 之後具名 subagent 的 PermissionRequest 變不了橘（今天停在 done）")
    func gapB_namedSubagentPermissionRequestCannotTurnLightOrange() throws {
        var s = Self.merge(try Self.measured("Stop"), into: nil)
        #expect(s.mainActivity == .done)

        let subAsksPermission = try #require(HookPayload(json: [
            "hook_event_name": "PermissionRequest", "session_id": s.sessionID,
            "agent_id": "a0b503d0b03dbd023", "agent_type": "general-purpose",
            "tool_name": "Bash", "tool_input": ["description": "刪掉建置產物"],
        ]))
        #expect(subAsksPermission.effect == .setActivity(.waiting),
                "事件本身的映射是 waiting —— 落差發生在 MergeRules 決定要不要採用它")

        s = Self.merge(subAsksPermission, into: s, after: 12)

        #expect(s.effectiveActivity == .done, """
            **已知落差 B**：背景具名 subagent 在等你批准，燈卻是綠的。
            修好之後這一行應該是 .waiting（橘燈）。
            """)
        #expect(s.toolDescription == "刪掉建置產物",
                "諷刺的是「在等什麼」這個欄位有被存下來，只是燈號用不到它")
    }

    // MARK: - 落差 C：從屬槽的殘影

    /// **今天：subagent 結束了，面板副行還掛著它最後用的 tool。**
    ///
    /// `SubagentStop` 在 `EventMapping` 對應 `.setActivity(.working)`。對**主**槽而言那是
    /// 對的（subagent 回來了、主 agent 繼續工作），但同一個映射被拿去寫**從屬**槽，語意就反了：
    /// 「這個 subagent 結束了」被記成「這個 subagent 正在工作」。加上 `subTool`／`subAgentType`
    /// 都是 carry-forward，殘影會留到主槽走 done／error 為止。
    @Test("落差 C：SubagentStop 之後，從屬槽仍顯示它在工作、tool 名不清（殘影）")
    func gapC_subSlotKeepsFinishedSubagentLabel() throws {
        var s = Self.merge(try #require(HookPayload(json: [
            "hook_event_name": "PreToolUse", "session_id": "s1", "tool_name": "Bash",
        ])), into: nil)
        #expect(s.mainActivity == .working, "主槽在跑，所以 guard 不擋，從屬槽收得到事件")

        s = Self.merge(try #require(HookPayload(json: [
            "hook_event_name": "PostToolUse", "session_id": "s1",
            "agent_id": "a1", "agent_type": "Explore", "tool_name": "Grep",
        ])), into: s, after: 3)
        #expect(s.subActivity == .working)
        #expect(SessionReducer.subagentLabel(type: s.subAgentType, tool: s.subTool) == "Explore → Grep")

        // subagent 結束了（真實 payload：帶 agent_id、帶 agent_type、不帶 tool_name）
        s = Self.merge(try #require(HookPayload(json: [
            "hook_event_name": "SubagentStop", "session_id": "s1",
            "agent_id": "a1", "agent_type": "Explore",
        ])), into: s, after: 9)

        #expect(s.subActivity == .working, """
            **已知落差 C**：它已經結束了，從屬槽卻記成「正在工作」。
            修好之後這裡應該是 nil（從屬槽被清掉）。
            """)
        #expect(SessionReducer.subagentLabel(type: s.subAgentType, tool: s.subTool) == "Explore → Grep",
                "面板副行還掛著它最後用的 tool —— 使用者看到的「沒有任何反應」有一部分是這個殘影")

        // 對照組：主槽走到 done 才會清掉——所以殘影的存活期是「到這一輪結束為止」
        s = Self.merge(try #require(HookPayload(json: [
            "hook_event_name": "Stop", "session_id": "s1",
        ])), into: s, after: 20)
        #expect(s.subActivity == nil && s.subTool == nil, "既有行為：Stop 清空從屬槽")
    }
}
