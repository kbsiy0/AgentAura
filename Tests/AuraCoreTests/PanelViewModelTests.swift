import Testing
import Foundation
@testable import AuraCore

@Suite("面板呈現")
struct PanelViewModelTests {

    let now = Date(timeIntervalSince1970: 1_788_700_000)

    func state(_ id: String, _ a: Activity, tool: String? = nil,
               turnStart: Double? = nil, subagents: [String: Int] = [:],
               failures: Int = 0, updated: Double = 0, live: Bool = true,
               model: String? = "claude-opus-5", lastMessage: String? = nil,
               toolError: String? = nil) -> SessionState {
        SessionState(id: id, projectName: id, projectPath: "/x/\(id)",
                     permissionMode: "default", effort: "high", model: model,
                     activity: a, mainActivity: a, subActivity: nil,
                     currentTool: tool, subagentTool: nil, toolDurationMs: nil,
                     turnStartedAt: turnStart.map { now.addingTimeInterval(-$0) },
                     subagents: subagents, toolFailures: failures,
                     lastMessage: lastMessage, errorType: nil, toolError: toolError,
                     liveness: live ? .alive(pid: 1) : .ended,
                     updatedAt: now.addingTimeInterval(-updated))
    }

    // ---- 排序：與 D1 優先序一致 ----

    @Test("排序是 error → waiting → working → done")
    func sortFollowsPriority() {
        let rows = PanelViewModel.rows(from: [
            state("w", .working), state("d", .done),
            state("e", .error), state("a", .waiting),
        ], now: now)
        #expect(rows.map { $0.id } == ["e", "a", "w", "d"])
    }

    @Test("同一組內最近活動優先")
    func recentFirstWithinGroup() {
        let rows = PanelViewModel.rows(from: [
            state("old", .working, updated: 300),
            state("new", .working, updated: 5),
            state("mid", .working, updated: 60),
        ], now: now)
        #expect(rows.map { $0.id } == ["new", "mid", "old"])
    }

    @Test("已結束的排在同組下半部")
    func endedGoesLast() {
        let rows = PanelViewModel.rows(from: [
            state("ended", .done, updated: 5, live: false),
            state("alive", .done, updated: 300, live: true),
        ], now: now)
        #expect(rows.map { $0.id } == ["alive", "ended"], "活著的優先，即使它更久沒動")
    }

    // ---- 內容 ----

    @Test("waiting 的主行說出在等什麼，不只是 tool 名")
    func waitingHeadlineNamesWhatIsAsked() {
        let rows = PanelViewModel.rows(from: [state("p", .waiting, tool: "Bash")], now: now)
        let h = rows[0].headline
        #expect(h.contains("Bash"))
        #expect(h.contains("等") || h.contains("批准"), "要看得出是在等你，實際：\(h)")
    }

    @Test("working 的主行顯示目前的 tool")
    func workingHeadlineShowsTool() {
        let rows = PanelViewModel.rows(from: [state("p", .working, tool: "Edit")], now: now)
        #expect(rows[0].headline.contains("Edit"))
    }

    @Test("done 的主行顯示完成訊息的摘要")
    func doneHeadlineShowsMessage() {
        let long = String(repeating: "完成了很多事情。", count: 40)
        let rows = PanelViewModel.rows(from: [state("p", .done, lastMessage: long)], now: now)
        #expect(rows[0].headline.count <= 90, "摘要要截斷，實際 \(rows[0].headline.count) 字")
        #expect(!rows[0].headline.isEmpty)
    }

    @Test("error 的主行顯示錯誤訊息")
    func errorHeadlineShowsError() {
        let rows = PanelViewModel.rows(from: [
            state("p", .error, toolError: "overloaded_error"),
        ], now: now)
        #expect(rows[0].headline.contains("overloaded_error"))
    }

    @Test("副行含本輪時長、subagent 數、失敗數")
    func detailHasCounters() {
        let rows = PanelViewModel.rows(from: [
            state("p", .working, turnStart: 487, subagents: ["Explore": 2, "implementer": 1], failures: 3),
        ], now: now)
        let d = rows[0].detail
        #expect(d.contains("8m") || d.contains("8 m") || d.contains("487"), "要有本輪時長，實際：\(d)")
        #expect(d.contains("3"), "要有 subagent 總數 3，實際：\(d)")
        #expect(d.contains("失敗") || d.contains("fail"), "要有失敗數，實際：\(d)")
    }

    @Test("沒有計數時副行不顯示 0，避免視覺噪音")
    func detailOmitsZeros() {
        let rows = PanelViewModel.rows(from: [state("p", .working)], now: now)
        #expect(!rows[0].detail.contains("0 subagent"))
        #expect(!rows[0].detail.contains("0 失敗"))
    }

    @Test("meta 含模型與 permission_mode")
    func metaHasModelAndMode() {
        let rows = PanelViewModel.rows(from: [state("p", .working)], now: now)
        #expect(rows[0].meta.contains("opus"))
        #expect(rows[0].meta.contains("default"))
    }

    @Test("模型缺失時 meta 不顯示空白欄位")
    func metaHandlesMissingModel() {
        let rows = PanelViewModel.rows(from: [state("p", .working, model: nil)], now: now)
        #expect(!rows[0].meta.hasPrefix(" ·"), "不得留下懸空的分隔符，實際：\(rows[0].meta)")
        #expect(rows[0].meta.contains("default"))
    }

    // ---- 時間格式化與時鐘倒退 ----

    @Test("時鐘倒退時不顯示負數")
    func clockSkewClampsToZero() {
        // updatedAt 在未來
        let s = state("p", .working, updated: -600)
        let rows = PanelViewModel.rows(from: [s], now: now)
        #expect(!rows[0].relativeTime.contains("-"), "實際：\(rows[0].relativeTime)")
    }

    @Test("turnStartedAt 在未來時，本輪時長不是負數")
    func futureTurnStartClamps() {
        let s = state("p", .working, turnStart: -300)
        let rows = PanelViewModel.rows(from: [s], now: now)
        #expect(!rows[0].detail.contains("-"), "實際：\(rows[0].detail)")
    }

    @Test("時長格式在各量級都可讀")
    func durationFormatting() {
        #expect(PanelViewModel.duration(0) == "0s")
        #expect(PanelViewModel.duration(45).contains("45"))
        #expect(PanelViewModel.duration(90).contains("1m"))
        #expect(PanelViewModel.duration(3_700).contains("1h"))
        #expect(PanelViewModel.duration(-5) == "0s", "負數 clamp 到 0")
    }

    // ---- 標題 ----

    @Test("標題把「有人在等你」放在最前面")
    func titleLeadsWithAttention() {
        let icon = IconState(activity: .waiting,
                             counts: [.waiting: 1, .working: 2], liveCount: 3)
        let t = PanelViewModel.title(for: icon)
        #expect(t.contains("1"))
        #expect(t.contains("等"), "實際：\(t)")
    }

    @Test("沒有 session 時標題明確說沒有，不留空白")
    func titleWhenEmpty() {
        #expect(!PanelViewModel.title(for: .empty).isEmpty)
    }
}
