import Testing
import Foundation
@testable import AuraCore

/// **T23：主槽靜止之後的具名 subagent 狀態優先序。**
///
/// 2026-09-11 使用者實機回報「燈號是綠色或等待色，但畫面上其實沒有任何事在發生」。
/// 審計（`docs/2026-09-11-subagent-state-priority-audit.html`）找到五個成因，其中
/// A／B／C 三個是真的落差。使用者當時裁決 **(c)：先釘住現況、寫進 known gaps，
/// phase 2 收尾後再開一輪修邏輯**——這個 suite 當初就是那次「先釘住」的產物，
/// 三條 `gapA_`／`gapB_`／`gapC_` 刻意斷言「今天的錯」。T23 是那「再開一輪修邏輯」，
/// 三條都已改寫成新契約（連測試名裡的 `gap` 前綴一起拿掉）。
///
/// 第一條 `measuredNamedSubagentPayloadShape` 是**平台實測契約**，修的時候不得放寬：
/// 整個修法（用 `agent_type` 分辨具名／內部、用 `agent_id` 把結束配回開始）就站在它上面。
///
/// 落差成因都在 `MergeRules.merge` 的這一行（§2.5.1）：
/// ```swift
/// guard !s.mainActivity.isQuiescent else { break }
/// ```
/// 它是用**內部** subagent 的證據寫出來的（`agent_type` 空字串、Stop 後 2.58s–186s 才到，
/// 見 `FixtureIntegrityTests.round2SubagentStopAfterStop`），卻套用在**所有** subagent 事件上。
/// 修法**不改這條 guard**：另開 `SessionSnapshot.outstandingSubagents`（keyed by `agent_id`）
/// 當燈號的第三個輸入，這條 guard 只繼續管「從屬槽」（`subActivity`／`subTool`／`subAgentType`）——
/// 這是唯一被 mutation 反證過安全的形狀（審計 §6.4 的實測記錄）。
@Suite("T23：主槽靜止之後的具名 subagent（審計 2026-09-11，修法見審計 §6）")
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

    // MARK: - 落差 A（已修）：主 agent 講完話之後，背景具名 subagent 還在跑

    /// **修好之後：燈回到 working，因為背景還有具名 subagent 在外面。**
    ///
    /// 主 agent 送 `Stop` 之後，`clearSubSlot` 清空從屬槽、`isQuiescent` guard 讓之後
    /// 所有 subagent 事件都被「從屬槽」丟掉——這件事**沒有變**（`subActivity` 依然是
    /// nil，見下方斷言）。改變的是 `outstandingSubagents` 這個第三個輸入：它獨立於
    /// 這條 guard 之外，用 `agent_id` 記住這個具名 subagent 還沒回來。實測 `round1`
    /// 有一個 `implementer` subagent 在 42 秒內連送 14 個 tool 事件，那段期間主槽
    /// 完全有可能已經 done——這個測試釘住的就是那個情境修好之後的樣子。
    @Test("落差 A 已修：Stop 之後具名 subagent 的 tool 事件讓燈回到 working，SubagentStop 抵達後燈回到 done")
    func backgroundNamedSubagentKeepsLightWorking() throws {
        var s = Self.merge(try Self.measured("Stop"), into: nil)
        #expect(s.mainActivity == .done)

        // 真實形狀：帶 agent_id 與非空 agent_type 的 PostToolUse（取自 round1 的 implementer）。
        let namedTool = try #require(HookPayload(json: [
            "hook_event_name": "PostToolUse", "session_id": s.sessionID,
            "agent_id": "adad9c77b1e0f4a21", "agent_type": "implementer", "tool_name": "Bash",
        ]))
        #expect(namedTool.isSubagent && namedTool.agentType == "implementer")

        s = Self.merge(namedTool, into: s, after: 8)

        #expect(s.subActivity == nil,
                "從屬槽仍受 §2.5.1 那條 guard 保護，完全不受這次修法影響——第三個輸入是獨立欄位")
        #expect(s.outstandingSubagents == ["adad9c77b1e0f4a21": .working],
                "具名 subagent 用 agent_id 記進集合，帶著它自己回報的 activity")
        #expect(s.effectiveActivity == .working, """
            **落差 A 已修**：背景具名 subagent 還在跑，燈必須是 working——不是「有結果可看」。
            """)
        #expect(s.writtenAt == Self.t0.addingTimeInterval(8), "時戳照樣更新（既有行為）")

        // 該 subagent 自己送 SubagentStop → 從集合移除，燈才能真的回到 done。
        let namedStop = try #require(HookPayload(json: [
            "hook_event_name": "SubagentStop", "session_id": s.sessionID,
            "agent_id": "adad9c77b1e0f4a21", "agent_type": "implementer",
        ]))
        s = Self.merge(namedStop, into: s, after: 10)
        #expect(s.outstandingSubagents?.isEmpty ?? true, "SubagentStop 抵達且 agent_id 在集合裡 → 移除")
        #expect(s.effectiveActivity == .done, "它真的回來了，燈才回到 done")
    }

    // MARK: - 落差 B（已修）：背景具名 subagent 在等使用者決策

    /// **修好之後：燈變橘，因為背景 subagent 在等你批准。**
    ///
    /// 這是既有 invariant「`waiting` 不得進入已結束未確認的尾巴」（不該橘卻橘）的**鏡像**：
    /// 該橘卻不橘。同一條 guard 造成的，只是方向相反——`outstandingSubagents` 記的不只是
    /// 「還在外面」，還帶著它自己回報的 activity，所以 `PermissionRequest` 記得進去的是
    /// `.waiting` 而不是固定的 `.working`（審計 §6.2）。
    ///
    /// **這個組合沒有實測樣本**——探針那次沒有撞到需要批准的 tool。`agent_id` 的形狀取自
    /// 實測（round3），事件名取自 `EventMapping.handledEvents`。這條測的是「我們的規則
    /// 怎麼處理這個形狀」，不是「平台一定會送這個形狀」。
    @Test("落差 B 已修：Stop 之後具名 subagent 的 PermissionRequest 讓燈變橘")
    func backgroundNamedSubagentPermissionRequestTurnsLightOrange() throws {
        var s = Self.merge(try Self.measured("Stop"), into: nil)
        #expect(s.mainActivity == .done)

        let subAsksPermission = try #require(HookPayload(json: [
            "hook_event_name": "PermissionRequest", "session_id": s.sessionID,
            "agent_id": "a0b503d0b03dbd023", "agent_type": "general-purpose",
            "tool_name": "Bash", "tool_input": ["description": "刪掉建置產物"],
        ]))
        #expect(subAsksPermission.effect == .setActivity(.waiting),
                "事件本身的映射是 waiting —— 修法要讓 MergeRules 真的採用它")

        s = Self.merge(subAsksPermission, into: s, after: 12)

        #expect(s.outstandingSubagents == ["a0b503d0b03dbd023": .waiting],
                "集合裡存的是這個 subagent 自己的 activity，不是寫死的 .working")
        #expect(s.effectiveActivity == .waiting, """
            **落差 B 已修**：背景具名 subagent 在等你批准，燈必須是橘的。
            """)
        #expect(s.toolDescription == "刪掉建置產物",
                "「在等什麼」這個欄位本來就存得到，現在燈號也真的用到了它所代表的狀態")
    }

    // MARK: - 內部 subagent 的排除（真實 payload，不是手搓的）

    /// **用 round2 真實 payload 重新驗證：內部 subagent 從不進 `outstandingSubagents`。**
    ///
    /// `internalSubagentStopAfterStopIsIgnored`（`MergeRulesTests`）已經用手搓的
    /// payload 釘住「§2.5.1 那條 guard 對從屬槽仍然有效」。這條額外拿 round2 **真實**
    /// 捕獲到的 `SubagentStop`（`agent_type` 是空字串，`HookPayload` 正規化成 nil）
    /// 過一次新加的 `outstandingSubagents` 路徑——排除條件是 `agentType != nil`，
    /// 不是又一次「主槽是否靜止」的猜測，兩者必須分開驗證，各自的資料本身才是依據。
    @Test("真實 round2 payload：內部 subagent 的遲到 SubagentStop 不進具名集合，燈維持 done")
    func internalSubagentFromRealFixtureNeverEntersOutstandingSet() throws {
        let raw = try Fixtures.events(named: "round2", kind: "SubagentStop")
        let internalStop = try #require(raw.first { ($0["agent_type"] as? String) == "" },
                                         "round2 必須含至少一筆 agent_type 空字串的 SubagentStop")
        let payload = try #require(HookPayload(json: internalStop))
        #expect(payload.agentType == nil, "HookPayload 已把空字串正規化為 nil")

        var s = Self.merge(try #require(HookPayload(json: [
            "hook_event_name": "Stop", "session_id": payload.sessionID,
        ])), into: nil)
        #expect(s.mainActivity == .done)

        s = Self.merge(payload, into: s, after: 60)

        #expect(s.outstandingSubagents == nil,
                "agent_type 為 nil → 從不進集合，不必再靠猜主槽狀態")
        #expect(s.effectiveActivity == .done,
                "拿真實 payload 而非手搓資料，重新驗證新設計下 §2.5.1 依然成立")
    }

    /// **S2-3（T23 review）：`p.agentType != nil` 這道排除條件本身缺乏見證。**
    ///
    /// 上面那條測試用的 round2 `SubagentStop` 走的是 `updateOutstandingSubagents`
    /// 的 **remove** 分支——就算拿掉 `agentType != nil` 這道排除，
    /// `removeValue(forKey:)` 對從沒被加進去的 key 一樣是 no-op，斷言照樣通過。
    /// 也就是說那條測試**沒有真的見證這道排除條件**，只是恰好被「remove 對空
    /// key 天生無害」這條不相干的路徑滿足了。
    ///
    /// 這道排除真正要擋的是 §2.5.1 原始 bug 在新層復發：內部 subagent 若送出
    /// **會進集合的事件**（不是 `SubagentStop`），沒有排除就會被 upsert 進去。
    /// 目前沒有內部 subagent 送非 SubagentStop 事件的真實 fixture 樣本，所以這裡
    /// 手搓（不是取自檔案），直接驗證排除條件本身而不是繞道驗證。
    @Test("內部 subagent 若送出會進集合的事件（不是 SubagentStop），排除條件必須擋下來")
    func internalSubagentNonStopEventNeverEntersOutstandingSet() throws {
        let internalToolEvent = try #require(HookPayload(json: [
            "hook_event_name": "PreToolUse", "session_id": "s1",
            "agent_id": "a8c360a1fe475f199", "agent_type": "", "tool_name": "Bash",
        ]))
        #expect(internalToolEvent.isSubagent && internalToolEvent.agentType == nil,
                "agent_id 存在但 agent_type 空字串已被 HookPayload 正規化成 nil")

        let s = Self.merge(internalToolEvent, into: nil)

        #expect(s.outstandingSubagents == nil, """
            排除條件（agentType != nil）必須擋下這個事件，不能只因為它不是
            SubagentStop 就漏網——這才是真正防 §2.5.1 原 bug 在新層復發的見證。
            """)
    }

    // MARK: - 保險：UserPromptSubmit 清空集合（S1-2，先前零測試）

    /// **S1-2（T23 review）：審計 §7 的保險先前完全沒有測試見證。**
    ///
    /// `MergeRules.applyCounters` 在 `UserPromptSubmit` 把 `outstandingSubagents`
    /// 重設為 nil——這是唯一擋「具名 subagent 崩潰、從此再也不會送 SubagentStop」
    /// 的保險（審計 §7 風險評估）。reviewer 把那行拿掉，28 個既有測試全綠：因為
    /// 沒有任何測試直接斷言這個欄位在新一輪之後真的被清空。
    @Test("保險：UserPromptSubmit（新一輪）清空 outstandingSubagents")
    func userPromptSubmitClearsOutstandingSubagentsAsSafetyNet() throws {
        var s = Self.merge(try Self.measured("Stop"), into: nil)
        let namedTool = try #require(HookPayload(json: [
            "hook_event_name": "PostToolUse", "session_id": s.sessionID,
            "agent_id": "adad9c77b1e0f4a21", "agent_type": "implementer", "tool_name": "Bash",
        ]))
        s = Self.merge(namedTool, into: s, after: 8)
        #expect(s.outstandingSubagents == ["adad9c77b1e0f4a21": .working])

        // 這個具名 subagent 崩潰了——從此再也不會送 SubagentStop，集合本來會卡住。
        let newTurn = try #require(HookPayload(json: [
            "hook_event_name": "UserPromptSubmit", "session_id": s.sessionID,
        ]))
        s = Self.merge(newTurn, into: s, after: 20)

        #expect(s.outstandingSubagents == nil, """
            審計 §7 的保險：具名 subagent 崩潰沒送 SubagentStop，新一輪必須清空
            這個欄位，否則燈永遠卡在 working。這條保險先前完全沒有測試見證過。
            """)
    }

    // MARK: - 落差 C（已修）：從屬槽的殘影

    /// **修好之後：subagent 結束時，從屬槽跟著清空，不再顯示它最後用的 tool。**
    ///
    /// `SubagentStop` 在 `EventMapping` 對應 `.setActivity(.working)`。對**主**槽而言那是
    /// 對的（subagent 回來了、主 agent 繼續工作），但同一個映射如果直接拿去寫**從屬**槽，
    /// 語意就反了：「這個 subagent 結束了」被記成「這個 subagent 正在工作」。修法不改
    /// `EventMapping` 的回傳值（主槽仍然需要 `.working`），而是在 `MergeRules` 的 sub
    /// 分支裡對 `SubagentStop` 特判成清除，讓 `subTool`／`subAgentType` 不再殘留成
    /// carry-forward。
    @Test("落差 C 已修：SubagentStop 之後從屬槽被清空，面板副行不再顯示它的 tool")
    func subSlotClearsWhenSubagentStops() throws {
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
        #expect(s.outstandingSubagents == ["a1": .working],
                "同一個具名 subagent 事件也會進第三個輸入的集合——兩件事互不影響")

        // subagent 結束了（真實 payload：帶 agent_id、帶 agent_type、不帶 tool_name）
        s = Self.merge(try #require(HookPayload(json: [
            "hook_event_name": "SubagentStop", "session_id": "s1",
            "agent_id": "a1", "agent_type": "Explore",
        ])), into: s, after: 9)

        #expect(s.subActivity == nil, """
            **落差 C 已修**：它已經結束了，從屬槽必須清掉，不能記成「正在工作」。
            """)
        #expect(s.subTool == nil && s.subAgentType == nil, "carry-forward 的殘影一起清掉")
        #expect(SessionReducer.subagentLabel(type: s.subAgentType, tool: s.subTool) == nil,
                "面板副行不再顯示它已經結束的 tool")
        #expect(s.outstandingSubagents?.isEmpty ?? true, "集合那邊也同時移除，兩件事一致")

        // 對照組：主槽走到 done 一樣會清從屬槽（既有行為，這裡只是確認沒有被這次修法動到）
        s = Self.merge(try #require(HookPayload(json: [
            "hook_event_name": "Stop", "session_id": "s1",
        ])), into: s, after: 20)
        #expect(s.subActivity == nil && s.subTool == nil, "既有行為：Stop 清空從屬槽")
    }
}
