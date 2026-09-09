import Testing
import Foundation
@testable import AuraCore

@Suite("SessionReducer")
struct SessionReducerTests {

    let probe = StubLiveness(table: [4242: 111])

    func snapshot(_ mutate: (inout SessionSnapshot) -> Void) -> SessionSnapshot {
        var s = SessionSnapshot(sessionID: "s1")
        s.pid = 4242; s.pidStartedAt = 111
        s.cwd = "/Users/you/Code/Vibe/payments-api"
        s.writtenAt = Date(timeIntervalSince1970: 1_788_628_000)
        mutate(&s)
        return s
    }

    @Test("activity 取兩槽 max —— waiting 不被 working 蓋掉")
    func activityTakesMax() {
        let s = snapshot { $0.mainActivity = .waiting; $0.subActivity = .working }
        let st = SessionReducer.state(from: s, liveness: probe)
        #expect(st.activity == .waiting)
        #expect(st.mainActivity == .waiting)
        #expect(st.subActivity == .working)
    }

    @Test("error 勝過 waiting（D1）")
    func errorBeatsWaiting() {
        let s = snapshot { $0.mainActivity = .error; $0.subActivity = .waiting }
        #expect(SessionReducer.state(from: s, liveness: probe).activity == .error)
    }

    /// D1 的**反方向**：subagent 的活動優先序較高時，由它把結果往上頂。
    ///
    /// 這個方向曾經全專案零覆蓋 —— `activityTakesMax` 與 `errorBeatsWaiting`
    /// 都把較高優先序放在 `mainActivity`，所以把 `effectiveActivity` 改成
    /// `{ mainActivity }`（完全忽略 subActivity），121 個測試無一變紅。
    ///
    /// 真實情境：主槽 `working`（非靜止態，§2.5.1 的 guard 放行）＋ subagent
    /// 自己的 tool 觸發 `PermissionRequest` → `subActivity = .waiting`。
    /// 這條壞掉的後果是使用者漏看「subagent 正在等你」。
    @Test("subagent 優先序較高時由它決定結果 —— D1 的反方向")
    func subActivityRaisesEffectiveActivity() {
        let waiting = snapshot { $0.mainActivity = .working; $0.subActivity = .waiting }
        #expect(waiting.effectiveActivity == .waiting)
        #expect(SessionReducer.state(from: waiting, liveness: probe).activity == .waiting)

        let err = snapshot { $0.mainActivity = .working; $0.subActivity = .error }
        #expect(err.effectiveActivity == .error)
        #expect(SessionReducer.state(from: err, liveness: probe).activity == .error)
    }

    @Test("專案名取 cwd 的 basename")
    func projectName() {
        #expect(SessionReducer.state(from: snapshot { _ in }, liveness: probe).projectName == "payments-api")
    }

    /// 斷言**具體值**，不是「非空」。
    ///
    /// `!name.isEmpty` 無法區分兩個 fallback：實測把 `"(unknown)"` 與 `"(root)"`
    /// 都改成同一個 `"x"`，這條測試照樣通過。而面板上「(unknown)」（沒有 cwd）
    /// 與「(root)」（cwd 是根目錄）對使用者除錯是不同訊息。
    @Test("cwd 缺失與根目錄給出兩個可區分的替代名")
    func projectNameFallback() {
        func name(_ cwd: String?) -> String {
            SessionReducer.state(from: snapshot { $0.cwd = cwd }, liveness: probe).projectName
        }
        #expect(name(nil) == "(unknown)")
        #expect(name("") == "(unknown)")
        #expect(name("/") == "(root)")
        #expect(name(nil) != name("/"), "兩個 fallback 必須可區分")
    }

    @Test("unicode / emoji 專案名保留完整")
    func projectNameUnicode() {
        let s = snapshot { $0.cwd = "/Users/you/專案 🚀/fitness-tracker-測試" }
        #expect(SessionReducer.state(from: s, liveness: probe).projectName == "fitness-tracker-測試")
    }

    @Test("subagentTool 組成 「型別 → tool」 形式")
    func subagentToolLabel() {
        let s = snapshot { $0.subAgentType = "Explore"; $0.subTool = "Grep"; $0.subActivity = .working }
        #expect(SessionReducer.state(from: s, liveness: probe).subagentTool == "Explore → Grep")
    }

    @Test("subagent 槽為空時 subagentTool 為 nil")
    func subagentToolNilWhenEmpty() {
        #expect(SessionReducer.state(from: snapshot { _ in }, liveness: probe).subagentTool == nil)
    }

    /// `subagentLabel` 的四種 (type, tool) 組合都要有樣本。
    ///
    /// 兩個混合 nil 的分支曾經從未被觸及：把 `case (t?, nil)` 與 `case (nil, u?)`
    /// 各自改成 `return nil`，`SessionReducerTests` 都是 12/12 全綠。
    /// 「有型別、沒 tool」是真實的中間狀態 —— `SubagentStart` 剛發生、
    /// `PreToolUse` 還沒到。
    @Test("subagentTool 的四種組合都有覆蓋")
    func subagentToolAllCombinations() {
        func label(type: String?, tool: String?) -> String? {
            let s = snapshot { $0.subAgentType = type; $0.subTool = tool; $0.subActivity = .working }
            return SessionReducer.state(from: s, liveness: probe).subagentTool
        }
        #expect(label(type: "Explore", tool: "Grep") == "Explore → Grep")
        #expect(label(type: "Explore", tool: nil) == "Explore")
        #expect(label(type: nil, tool: "Grep") == "Grep")
        #expect(label(type: nil, tool: nil) == nil)
    }

    @Test("pid 活著 → liveness 為 alive")
    func aliveWhenPIDMatches() {
        #expect(SessionReducer.state(from: snapshot { _ in }, liveness: probe).liveness == .alive(pid: 4242))
    }

    @Test("啟動時戳不符 → ended（pid 回收）")
    func endedWhenStartTimeMismatch() {
        let s = snapshot { $0.pidStartedAt = 999 }
        #expect(SessionReducer.state(from: s, liveness: probe).liveness == .ended)
    }

    @Test("terminated 旗標直接判 ended，不查 pid")
    func terminatedIsEnded() {
        let s = snapshot { $0.terminated = true }
        #expect(SessionReducer.state(from: s, liveness: probe).liveness == .ended)
    }

    @Test("pid 或 pidStartedAt 缺失時視為 ended")
    func missingPIDInfoIsEnded() {
        #expect(SessionReducer.state(from: snapshot { $0.pid = nil }, liveness: probe).liveness == .ended)
        #expect(SessionReducer.state(from: snapshot { $0.pidStartedAt = nil }, liveness: probe).liveness == .ended)
    }

    @Test("errorType 取自 reason 欄位")
    func errorTypeFromReason() {
        let s = snapshot { $0.mainActivity = .error; $0.reason = "overloaded_error" }
        #expect(SessionReducer.state(from: s, liveness: probe).errorType == "overloaded_error")
    }

    /// **資料流四段的第三段 gate**（payload → 檔案 → **state** → UI）。
    ///
    /// `SessionState` 的 doc-comment 寫著「修一條資料流要走完四段」——
    /// 但那句話先前**沒有任何 gate**。實證：把 `SessionReducer` 裡
    /// `toolDescription: s.toolDescription` 改成 `nil`，14 條測試無一變紅
    /// （最終 review 的 I3：`toolDescription` / `notificationMessage` 存得到、
    /// 送不出去，而面板顯示的正是 `HookPayload` 自己判定「不夠」的那個字串）。
    ///
    /// 這條用 `Mirror` 從**輸出端**推導：餵一個每個欄位都有值的 snapshot，
    /// 產出的 `SessionState` 裡任何 `nil` 都代表那個欄位沒接上。
    /// 新增欄位忘了接、既有欄位被改斷，兩個方向都會紅。
    @Test("snapshot 的每個欄位都走得到 SessionState —— 沒有半路掉的")
    func reducerCarriesEveryField() {
        let s = snapshot {
            $0.cwd = "/Users/you/Code/Vibe/payments-api"
            $0.permissionMode = "default"
            $0.effort = "xhigh"
            $0.model = "claude-opus-5"
            $0.reason = "overloaded_error"
            $0.mainActivity = .error
            $0.mainTool = "Bash"
            $0.subActivity = .working
            $0.subTool = "Grep"
            $0.subAgentType = "Explore"
            $0.notificationMessage = "Claude is waiting for your input"
            $0.lastMessage = "全部完成"
            $0.toolDescription = "Download example.com to dl2.html"
            $0.toolError = "File does not exist"
            $0.toolDurationMs = 12_403
            $0.turnStartedAt = Date(timeIntervalSince1970: 1_788_628_000)
            $0.subagents = ["Explore": 2]
            $0.toolFailures = 3
        }
        let st = SessionReducer.state(from: s, liveness: probe)

        let unwired = Mirror(reflecting: st).children
            .filter { String(describing: $0.value) == "nil" }
            .map { $0.label ?? "?" }
        #expect(unwired.isEmpty, """
            這些欄位沒有從 snapshot 走到 SessionState：\(unwired.sorted())
            資料流是 payload → 檔案 → state → UI 四段，這裡是第三段。
            前兩段有測試、第四段有測試，中間斷掉時先前沒有任何東西會紅。
            """)
    }
}
