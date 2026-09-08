import Testing
import Foundation

@Suite("Fixture 完整性")
struct FixtureIntegrityTests {

    @Test("round1 含 15 個 PreToolUse 與 14 個 PostToolUse")
    func round1Counts() throws {
        let all = try Fixtures.rawEvents(named: "round1") + Fixtures.rawEvents(named: "round1b")
        let counts = Dictionary(grouping: all) { $0["hook_event_name"] as? String ?? "?" }
            .mapValues(\.count)
        #expect(counts["PreToolUse"] == 15)
        #expect(counts["PostToolUse"] == 14)
        #expect(counts["SessionStart"] == 1)
        #expect(counts["Stop"] == 1)
        #expect(counts["SessionEnd"] == 1)
    }

    @Test("round1 的 effort 是物件形狀，不是字串")
    func effortIsObject() throws {
        let pre = try Fixtures.events(named: "round1", kind: "PreToolUse")
        let effort = try #require(pre.first?["effort"])
        #expect(effort is [String: Any], "實測 effort 是 {\"level\":…} 物件（spec §2.1.1）")
    }

    @Test("round1 沒有任何 event 帶 model，round2 的 SessionStart 有")
    func modelFieldOnlyOnSessionStart() throws {
        let r1 = try Fixtures.rawEvents(named: "round1") + Fixtures.rawEvents(named: "round1b")
        #expect(r1.allSatisfy { $0["model"] == nil }, "第一輪：無 model")

        let starts = try Fixtures.events(named: "round2", kind: "SessionStart")
        #expect(!starts.isEmpty)
        #expect(starts.allSatisfy { $0["model"] is String },
                "第二輪實測：SessionStart 帶 model（spec §2.1.1，第二輪為準）")
        // 其他 event 仍然不帶 —— 故 model 必須由 MergeRules 帶過來
        let others = try Fixtures.rawEvents(named: "round2")
            .filter { $0["hook_event_name"] as? String != "SessionStart" }
        #expect(others.allSatisfy { $0["model"] == nil })
    }

    @Test("round2 有捕獲 Notification，notification_type 與 message 皆經量測確認")
    func round2HasNotification() throws {
        let notifs = try Fixtures.events(named: "round2", kind: "Notification")
        #expect(!notifs.isEmpty, "Task 01 必須捕獲至少 1 筆 Notification")
        #expect(notifs.allSatisfy { $0["notification_type"] is String },
                "欄位名必須經實測確認，不能只靠文件")
        #expect(notifs.allSatisfy { $0["message"] is String },
                "實測發現的額外欄位（spec §2.1.2）")
    }

    @Test("round2 的 SubagentStop 有 agent_type 為空字串的內部 subagent")
    func round2HasInternalSubagent() throws {
        let stops = try Fixtures.events(named: "round2", kind: "SubagentStop")
        #expect(!stops.isEmpty)
        #expect(stops.contains { ($0["agent_type"] as? String) == "" },
                "內部 subagent 的 agent_type 是空字串而非 null —— §2.5.1 critical bug 的來源")
        #expect(stops.allSatisfy { ($0["agent_id"] as? String)?.isEmpty == false })
    }

    @Test("round2 裡 SubagentStop 出現在主 agent Stop 之後（§2.5.1 的時序證據）")
    func round2SubagentStopAfterStop() throws {
        // 探針的外層有 _t 時戳，rawEvents 已剝掉；這裡直接讀原始行。
        let url = try #require(Bundle.module.url(forResource: "Fixtures/round2", withExtension: "ndjson"))
        struct Row { let t: Double; let sid: String; let event: String; let isSub: Bool }
        let rows: [Row] = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n").compactMap { line in
                guard let d = line.data(using: .utf8),
                      let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let t = o["_t"] as? Double,
                      let p = o["_payload"] as? [String: Any],
                      let sid = p["session_id"] as? String,
                      let ev = p["hook_event_name"] as? String else { return nil }
                return Row(t: t, sid: sid, event: ev,
                           isSub: (p["agent_id"] as? String)?.isEmpty == false)
            }
        var found = false
        for sid in Set(rows.map(\.sid)) {
            let mine = rows.filter { $0.sid == sid }
            guard let stop = mine.first(where: { $0.event == "Stop" && !$0.isSub })?.t,
                  let subStop = mine.first(where: { $0.event == "SubagentStop" })?.t
            else { continue }
            if subStop > stop { found = true }
        }
        #expect(found, "至少一個 session 的 SubagentStop 晚於 Stop —— 這是 §2.5.1 的實測依據")
    }
}
