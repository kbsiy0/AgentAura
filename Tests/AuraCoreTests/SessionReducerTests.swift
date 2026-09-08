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

    @Test("專案名取 cwd 的 basename")
    func projectName() {
        #expect(SessionReducer.state(from: snapshot { _ in }, liveness: probe).projectName == "payments-api")
    }

    @Test("cwd 為 nil 或空時給可讀的替代名，不得 crash")
    func projectNameFallback() {
        for cwd in [nil, "", "/"] {
            let s = snapshot { $0.cwd = cwd }
            let name = SessionReducer.state(from: s, liveness: probe).projectName
            #expect(!name.isEmpty)
        }
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
}
