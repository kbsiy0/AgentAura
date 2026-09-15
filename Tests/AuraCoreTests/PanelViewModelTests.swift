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
        SessionState(id: id, projectName: id,
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
        ], now: now, language: .traditionalChinese)
        #expect(rows.map { $0.id } == ["e", "a", "w", "d"])
    }

    @Test("同一組內最近活動優先")
    func recentFirstWithinGroup() {
        let rows = PanelViewModel.rows(from: [
            state("old", .working, updated: 300),
            state("new", .working, updated: 5),
            state("mid", .working, updated: 60),
        ], now: now, language: .traditionalChinese)
        #expect(rows.map { $0.id } == ["new", "mid", "old"])
    }

    @Test("已結束的排在同組下半部")
    func endedGoesLast() {
        let rows = PanelViewModel.rows(from: [
            state("ended", .done, updated: 5, live: false),
            state("alive", .done, updated: 300, live: true),
        ], now: now, language: .traditionalChinese)
        #expect(rows.map { $0.id } == ["alive", "ended"], "活著的優先，即使它更久沒動")
    }

    // ---- 副行整行（S1-B：「已結束」在行首）----

    @Test("已結束的列：副行以「已結束 · 」起頭，後接 detail 與相對時間")
    func endedFooterLeadsWithEnded() {
        let rows = PanelViewModel.rows(from: [state("e", .done, turnStart: 192, updated: 120, live: false)], now: now, language: .traditionalChinese)
        let f = rows[0].footer
        #expect(f.hasPrefix("已結束 · "), "「已結束」是唯一的存活訊號，要在行首，實際：\(f)")
        #expect(!rows[0].detail.isEmpty && f.contains(rows[0].detail), "行首之後要有 detail，實際：\(f)")
        #expect(f.hasSuffix(rows[0].relativeTime), "最後是相對時間，實際：\(f)")
    }

    @Test("已結束但沒有 detail：不留懸空分隔符")
    func endedFooterWithoutDetail() {
        let rows = PanelViewModel.rows(from: [state("e", .done, updated: 120, live: false)], now: now, language: .traditionalChinese)
        #expect(rows[0].detail.isEmpty, "前提：無本輪、無 subagent、無失敗 → detail 空，實際：\(rows[0].detail)")
        #expect(rows[0].footer == "已結束 · \(rows[0].relativeTime)", "實際：\(rows[0].footer)")
    }

    @Test("活著的列副行不含「已結束」；活著且無 detail 時整行空（view 不畫，既有行為）")
    func aliveFooter() {
        let rows = PanelViewModel.rows(from: [state("a", .working, turnStart: 30), state("b", .working)], now: now, language: .traditionalChinese)
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let a = byID["a"]!, b = byID["b"]!
        #expect(!a.footer.contains("已結束") && a.footer.hasPrefix(a.detail), "實際：\(a.footer)")
        #expect(b.detail.isEmpty && b.footer.isEmpty, "活著且無 detail 不畫副行，實際 detail「\(b.detail)」footer「\(b.footer)」")
    }

    // ---- 內容 ----

    @Test("waiting 的主行說出在等什麼，不只是 tool 名")
    func waitingHeadlineNamesWhatIsAsked() {
        let rows = PanelViewModel.rows(from: [state("p", .waiting, tool: "Bash")], now: now, language: .traditionalChinese)
        let h = rows[0].headline
        #expect(h.contains("Bash"))
        #expect(h.contains("等") || h.contains("批准"), "要看得出是在等你，實際：\(h)")
    }

    @Test("working 的主行顯示目前的 tool")
    func workingHeadlineShowsTool() {
        let rows = PanelViewModel.rows(from: [state("p", .working, tool: "Edit")], now: now, language: .traditionalChinese)
        #expect(rows[0].headline.contains("Edit"))
    }

    @Test("done 的主行顯示完成訊息的摘要")
    func doneHeadlineShowsMessage() {
        let long = String(repeating: "完成了很多事情。", count: 40)
        let rows = PanelViewModel.rows(from: [state("p", .done, lastMessage: long)], now: now, language: .traditionalChinese)
        #expect(rows[0].headline.count <= 90, "摘要要截斷，實際 \(rows[0].headline.count) 字")
        #expect(!rows[0].headline.isEmpty)
    }

    @Test("error 的主行顯示錯誤訊息")
    func errorHeadlineShowsError() {
        let rows = PanelViewModel.rows(from: [
            state("p", .error, toolError: "overloaded_error"),
        ], now: now, language: .traditionalChinese)
        #expect(rows[0].headline.contains("overloaded_error"))
    }

    @Test("副行含本輪時長、subagent 數、失敗數")
    func detailHasCounters() {
        let rows = PanelViewModel.rows(from: [
            state("p", .working, turnStart: 487, subagents: ["Explore": 2, "implementer": 1], failures: 3),
        ], now: now, language: .traditionalChinese)
        let d = rows[0].detail
        #expect(d.contains("8m") || d.contains("8 m") || d.contains("487"), "要有本輪時長，實際：\(d)")
        #expect(d.contains("3"), "要有 subagent 總數 3，實際：\(d)")
        #expect(d.contains("失敗") || d.contains("fail"), "要有失敗數，實際：\(d)")
    }

    @Test("沒有計數時副行不顯示 0，避免視覺噪音")
    func detailOmitsZeros() {
        let rows = PanelViewModel.rows(from: [state("p", .working)], now: now, language: .traditionalChinese)
        #expect(!rows[0].detail.contains("0 subagent"))
        #expect(!rows[0].detail.contains("0 失敗"))
    }

    // T05（S1-Q5）：`meta` 現在套 `Jargon`，顯示的是人話不是原始代碼字。
    // 改前只驗證原始代碼字有沒有出現（`"opus"`／`"default"`）——那正是 T05 要拿掉的東西，
    // 所以這不是弱化，是對齊新契約：斷言從「代碼字在不在」換成「人話在不在、代碼字有沒有殘留」，
    // 淨 #expect 數從 2 條增加到 4 條。
    @Test("meta 顯示的是人話，不是原始代碼字（套用 Jargon）")
    func metaShowsPlainLanguageNotRawCodes() {
        let rows = PanelViewModel.rows(from: [state("p", .working)], now: now, language: .traditionalChinese)
        #expect(rows[0].meta.contains("Opus 5"), "應顯示映射後的模型名，實際：\(rows[0].meta)")
        #expect(rows[0].meta.contains("每次問我"), "應顯示映射後的 permission_mode，實際：\(rows[0].meta)")
        #expect(!rows[0].meta.contains("claude-opus-5"), "不得殘留原始代碼字，實際：\(rows[0].meta)")
        #expect(!rows[0].meta.contains("default"), "不得殘留原始代碼字，實際：\(rows[0].meta)")
    }

    @Test("模型缺失時 meta 不顯示空白欄位，且 permission_mode 仍是人話")
    func metaHandlesMissingModel() {
        let rows = PanelViewModel.rows(from: [state("p", .working, model: nil)], now: now, language: .traditionalChinese)
        #expect(!rows[0].meta.hasPrefix(" ·"), "不得留下懸空的分隔符，實際：\(rows[0].meta)")
        #expect(rows[0].meta.contains("每次問我"), "實際：\(rows[0].meta)")
        #expect(!rows[0].meta.contains("default"), "不得殘留原始代碼字，實際：\(rows[0].meta)")
    }

    // ---- 時間格式化與時鐘倒退 ----

    @Test("時鐘倒退時不顯示負數")
    func clockSkewClampsToZero() {
        // updatedAt 在未來
        let s = state("p", .working, updated: -600)
        let rows = PanelViewModel.rows(from: [s], now: now, language: .traditionalChinese)
        #expect(!rows[0].relativeTime.contains("-"), "實際：\(rows[0].relativeTime)")
    }

    @Test("turnStartedAt 在未來時，本輪時長不是負數")
    func futureTurnStartClamps() {
        let s = state("p", .working, turnStart: -300)
        let rows = PanelViewModel.rows(from: [s], now: now, language: .traditionalChinese)
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
        let t = PanelViewModel.title(for: icon, language: .traditionalChinese)
        #expect(t.contains("1"))
        #expect(t.contains("等"), "實際：\(t)")
    }

    @Test("沒有 session 時標題明確說沒有，不留空白")
    func titleWhenEmpty() {
        #expect(!PanelViewModel.title(for: .empty, language: .traditionalChinese).isEmpty)
    }

    // MARK: - 最終 review 的 I3 / I4

    /// **waiting 那一列要說出在等什麼**（spec §2.1.2 / §3.7）。
    ///
    /// `toolDescription` 先前只走完 payload → 檔案兩段，沒進 `SessionState`
    /// 也沒進面板 —— 面板顯示的正是 `HookPayload` 的 doc-comment 自己判定
    /// 「不夠」的那個字串「等你批准：Bash」。
    @Test("waiting 的主行用 toolDescription，不是只有 tool 名")
    func waitingHeadlineUsesToolDescription() {
        let s = state(.waiting, tool: "Bash", desc: "Download example.com to dl2.html")
        #expect(PanelViewModel.headline(for: s, language: .traditionalChinese) == "等你批准：Download example.com to dl2.html")
    }

    @Test("沒有 toolDescription 時退回 notificationMessage，再退回 tool 名")
    func waitingHeadlineFallbacks() {
        let m = state(.waiting, tool: "Bash", notif: "MCP server 在等你輸入")
        #expect(PanelViewModel.headline(for: m, language: .traditionalChinese) == "等你批准：MCP server 在等你輸入")
        let t = state(.waiting, tool: "Bash")
        #expect(PanelViewModel.headline(for: t, language: .traditionalChinese) == "等你批准：Bash")
    }

    /// **主 agent 的 tool 是主行，subagent 的是附註**（spec §2.5 結尾）。
    ///
    /// `MergeRules` 費了很大力氣保住 `mainTool` 不被 subagent 覆蓋
    /// （`mainToolNotOverwritten`），先前卻在呈現層又被覆蓋掉 ——
    /// 只要有 subagent 在跑，使用者就看不到主 agent 在做什麼。
    @Test("working 的主行是主 agent 的 tool，subagent 只出現在副行")
    func workingHeadlineKeepsMainTool() {
        let s = state(.working, tool: "Bash", sub: "Explore → Grep")
        #expect(PanelViewModel.headline(for: s, language: .traditionalChinese) == "Bash", "主行被 subagent 蓋掉了")
        #expect(PanelViewModel.detail(for: s, now: Date(), language: .traditionalChinese).contains("Explore → Grep"),
                "subagent 應以附註形式出現在副行")
    }

    @Test("沒有主 tool 時才退回 subagent 的")
    func workingHeadlineFallsBackToSubagent() {
        let s = state(.working, sub: "Explore → Grep")
        #expect(PanelViewModel.headline(for: s, language: .traditionalChinese) == "Explore → Grep")
    }

    @Test("tool 耗時出現在副行")
    func detailShowsToolDuration() {
        let s = state(.working, tool: "Bash", durationMs: 12_403)
        #expect(PanelViewModel.detail(for: s, now: Date(), language: .traditionalChinese).contains("12"), "應含 tool 耗時")
    }

    // MARK: - T23 review S2-4：主 agent 已完成，燈卻被背景具名 subagent 拖回 working

    /// **T23 A 修好之後，面板反而說謊了。**
    ///
    /// `effectiveActivity` 從 done 變 working（T23 A 的設計）之後，`headline`
    /// 的 `.working` 分支照舊回 `s.currentTool`——但那是主 agent**早就跑完**的
    /// tool。使用者會讀成「主 agent 還在跑 Bash」，比修 A 之前更糟：以前燈色
    /// 至少沒說謊（done），現在燈色對了、文字反而說謊。
    ///
    /// `SessionState.mainActivity` 早就存在（`activityTakesMax` 等測試已經在
    /// 用），不需要新欄位——`activity != mainActivity` 這件事本身就是「aggregate
    /// 被別人拖著跑」的訊號，`mainActivity == .done` 就是「背景 subagent 撐起
    /// working」這個情境的判準（推導見 T23 review 回報：main 若是 error 會直接
    /// 贏過 working，不會落到這個分支；若 mainActivity 也是 working 就是正常
    /// 前景工作，不該套用這段特例）。
    @Test("working 但 mainActivity 已 done：主行要說出「背景還有東西在跑」，不能沿用主 agent 的舊 tool 名")
    func workingHeadlineRevealsBackgroundSubagentWhenMainIsDone() {
        let s = state(.working, tool: "Bash", mainActivity: .done, lastMessage: "全部完成")

        let headline = PanelViewModel.headline(for: s, language: .traditionalChinese)
        #expect(headline != "Bash", "不能顯示主 agent 早就跑完的 tool，那會讓人誤以為主 agent 還在動")
        #expect(headline.contains("背景"), "主行必須說得出「背景還有東西在跑」這件事，不只是燈色對")

        #expect(PanelViewModel.detail(for: s, now: Date(), language: .traditionalChinese).contains("全部完成"),
                "主 agent 自己的完成訊息不能因為這個特例就不見了")
    }

    @Test("working 且 mainActivity 也是 working（正常前景工作）：headline 維持原本行為，不受這個特例影響")
    func workingHeadlineUnaffectedWhenMainIsStillWorking() {
        let s = state(.working, tool: "Bash", mainActivity: .working)
        #expect(PanelViewModel.headline(for: s, language: .traditionalChinese) == "Bash", "沒有背景 subagent 撐著時，行為不變")
    }

    /// 這幾條共用的建構器 —— 只填會用到的欄位，其餘給中性值。
    func state(_ a: Activity, tool: String? = nil, sub: String? = nil,
               desc: String? = nil, notif: String? = nil, durationMs: Int? = nil,
               mainActivity: Activity? = nil, lastMessage: String? = nil) -> SessionState {
        SessionState(id: "s1", projectName: "P",
                     permissionMode: nil, effort: nil, model: nil,
                     activity: a, mainActivity: mainActivity ?? a, subActivity: nil,
                     currentTool: tool, subagentTool: sub, toolDurationMs: durationMs,
                     turnStartedAt: nil, subagents: [:], toolFailures: 0,
                     lastMessage: lastMessage, errorType: nil, toolError: nil,
                     toolDescription: desc, notificationMessage: notif,
                     liveness: .alive(pid: 1), updatedAt: Date())
    }
}
