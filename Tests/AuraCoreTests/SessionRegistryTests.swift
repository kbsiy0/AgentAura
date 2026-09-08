import Testing
import Foundation
@testable import AuraCore

@Suite("SessionRegistry unacked 尾巴（§2.4）")
struct SessionRegistryTests {

    func state(_ id: String, _ a: Activity, live: Bool = true) -> SessionState {
        SessionState(id: id, projectName: id, projectPath: "/x/\(id)",
                     permissionMode: nil, effort: nil, model: nil,
                     activity: a, mainActivity: a, subActivity: nil,
                     currentTool: nil, subagentTool: nil, toolDurationMs: nil,
                     turnStartedAt: nil, subagents: [:], toolFailures: 0,
                     lastMessage: nil, errorType: nil, toolError: nil,
                     liveness: live ? .alive(pid: 1) : .ended,
                     updatedAt: Date(timeIntervalSince1970: 1_788_628_000))
    }

    @Test("活著的 session 都可見")
    func aliveSessionsVisible() {
        var r = SessionRegistry()
        r.upsert(state("a", .working))
        r.upsert(state("b", .waiting))
        #expect(Set(r.visible.map(\.id)) == ["a", "b"])
    }

    @Test("已結束但未確認的 error 仍參與聚合 —— 核心價值")
    func endedUnackedErrorStillVisible() {
        var r = SessionRegistry()
        r.upsert(state("a", .error, live: false))
        #expect(r.visible.map(\.id) == ["a"], "整夜 pipeline 掛掉、terminal 收掉，早上仍看得到")
    }

    @Test("已結束但未確認的 done 仍參與聚合")
    func endedUnackedDoneStillVisible() {
        var r = SessionRegistry()
        r.upsert(state("a", .done, live: false))
        #expect(r.visible.map(\.id) == ["a"])
    }

    @Test("PermissionRequest 後直接 SessionEnd（按 Deny 的實測序列）→ 不得留在尾巴")
    func endedWhileWaitingIsDropped() {
        var r = SessionRegistry()
        r.upsert(state("denied", .waiting, live: false))
        #expect(r.visible.isEmpty,
                "已結束、使用者早就按過 Deny 的 session 不得亮橘燈說「有人在等你」（§2.4.1）")
    }

    @Test("pid 死亡且卡在 waiting → 同樣丟棄")
    func deadWhileWaitingIsDropped() {
        var r = SessionRegistry()
        r.upsert(state("crashed", .waiting, live: false))
        r.upsert(state("alive", .working))
        #expect(r.visible.map(\.id) == ["alive"])
    }

    @Test("還活著的 waiting 仍然可見（那是真的在等你）")
    func aliveWaitingStaysVisible() {
        var r = SessionRegistry()
        r.upsert(state("w", .waiting))
        #expect(r.visible.map(\.id) == ["w"])
    }

    @Test("已結束且非靜止態（working/idle）直接不可見")
    func endedNonQuiescentDropped() {
        var r = SessionRegistry()
        r.upsert(state("a", .working, live: false))
        r.upsert(state("b", .idle, live: false))
        #expect(r.visible.isEmpty, "跑到一半被砍掉、沒有結果可看 → 不需要佔用注意力")
    }

    @Test("acknowledgeAll 一次確認全部未確認的，不論是否可見")
    func acknowledgeAllMarksEverything() {
        var r = SessionRegistry()
        r.upsert(state("a", .error, live: false))
        r.upsert(state("b", .done, live: false))
        r.upsert(state("c", .waiting))
        _ = r.acknowledgeAll()
        #expect(r.isAcknowledged("a"))
        #expect(r.isAcknowledged("b"))
        #expect(r.isAcknowledged("c"))
    }

    @Test("acknowledgeAll 回傳「已結束且已確認」的 id，供刪檔")
    func acknowledgeAllReturnsRemovable() {
        var r = SessionRegistry()
        r.upsert(state("ended1", .error, live: false))
        r.upsert(state("ended2", .done,  live: false))
        r.upsert(state("alive1", .waiting))
        #expect(Set(r.acknowledgeAll()) == ["ended1", "ended2"],
                "還活著的不刪 —— 它還會繼續寫入")
    }

    @Test("已確認且已結束者移出 registry，不再可見")
    func ackedEndedRemoved() {
        var r = SessionRegistry()
        r.upsert(state("a", .error, live: false))
        _ = r.acknowledgeAll()
        #expect(r.visible.isEmpty)
        #expect(r.states["a"] == nil)
    }

    @Test("已確認但還活著的 session 仍可見（它會繼續更新）")
    func ackedButAliveStaysVisible() {
        var r = SessionRegistry()
        r.upsert(state("a", .waiting))
        _ = r.acknowledgeAll()
        #expect(r.visible.map(\.id) == ["a"])
    }

    @Test("已確認的 session 再有新活動 → 重新變成未確認")
    func newActivityResetsAcknowledgement() {
        var r = SessionRegistry()
        r.upsert(state("a", .done))
        _ = r.acknowledgeAll()
        #expect(r.isAcknowledged("a"))

        r.upsert(state("a", .working))      // 使用者又下了新 prompt
        #expect(!r.isAcknowledged("a"), "新一輪的結果需要重新被看過")
    }

    @Test("remove 移除 session 與其確認狀態")
    func removeClearsBoth() {
        var r = SessionRegistry()
        r.upsert(state("a", .done, live: false))
        _ = r.acknowledgeAll()
        r.upsert(state("a", .working))
        r.remove("a")
        #expect(r.states["a"] == nil)
        #expect(!r.isAcknowledged("a"), "確認狀態也要清掉，否則同 id 重建後會被誤判為已看過")
        #expect(r.visible.isEmpty)
    }

    @Test("同一 session 重複 upsert 只保留最新")
    func upsertReplaces() {
        var r = SessionRegistry()
        r.upsert(state("a", .working))
        r.upsert(state("a", .waiting))
        #expect(r.states.count == 1)
        #expect(r.states["a"]?.activity == .waiting)
    }

    @Test("50 個 session 併存不出錯")
    func fiftySessions() {
        var r = SessionRegistry()
        for i in 0..<50 { r.upsert(state("s\(i)", i.isMultiple(of: 3) ? .waiting : .working)) }
        #expect(r.visible.count == 50)
        #expect(r.acknowledgeAll().isEmpty, "全部活著 → 沒有可刪的")
    }
}
