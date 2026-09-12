import Testing
import Foundation
@testable import AuraCore

@Suite("SessionRegistry unacked 尾巴（§2.4）")
struct SessionRegistryTests {

    /// `at` 的預設值與原本寫死的值相同，所以既有測試行為完全不變。
    /// 加這個參數是因為 `upsert` 的「時戳前進 → 撤銷確認」分支需要兩個
    /// 不同時戳的 state 才能觸及，而整份測試檔原本沒有任何一對。
    func state(_ id: String, _ a: Activity, live: Bool = true,
               at t: TimeInterval = 1_788_628_000) -> SessionState {
        SessionState(id: id, projectName: id,
                     permissionMode: nil, effort: nil, model: nil,
                     activity: a, mainActivity: a, subActivity: nil,
                     currentTool: nil, subagentTool: nil, toolDurationMs: nil,
                     turnStartedAt: nil, subagents: [:], toolFailures: 0,
                     lastMessage: nil, errorType: nil, toolError: nil,
                     liveness: live ? .alive(pid: 1) : .ended,
                     updatedAt: Date(timeIntervalSince1970: t))
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

    /// `acknowledgeAll` 對**還活著**的 session 留下「已確認」標記；
    /// 對**已結束**的直接整筆移除（回傳的 id 由呼叫端刪檔）。
    ///
    /// 這條先前斷言 `isAcknowledged("a")` / `isAcknowledged("b")`——
    /// 而 a / b 是已結束、會被移除的 session。那等於在斷言
    /// 「移除之後 `acknowledged` 仍留著它們」，也就是把**洩漏當成契約**。
    /// 對一個已經不存在、檔案也被刪掉的 id 問「確認過了嗎」沒有意義。
    /// 改成斷言真正的結果（移除 + 不留痕跡 + 活著的有標記），比原本更強。
    @Test("acknowledgeAll：活著的留標記，已結束的整筆移除且不留痕跡")
    func acknowledgeAllMarksEverything() {
        var r = SessionRegistry()
        r.upsert(state("a", .error, live: false))
        r.upsert(state("b", .done, live: false))
        r.upsert(state("c", .waiting))
        let removable = r.acknowledgeAll()

        #expect(Set(removable) == ["a", "b"], "已結束的才需要刪檔")
        for id in ["a", "b"] {
            #expect(r.states[id] == nil, "\(id) 應已從 states 移除")
            #expect(!r.isAcknowledged(id), "\(id) 也應從 acknowledged 移除 —— 否則就是洩漏")
        }
        #expect(r.states["c"] != nil, "還活著的不移除")
        #expect(r.isAcknowledged("c"), "還活著的留下已確認標記")
        #expect(r.visible.map(\.id) == ["c"], "確認後只剩活著的那個")
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

    /// `upsert` 的「時戳前進也要撤銷確認」分支。
    ///
    /// 這個分支曾經從未被觸及（整份測試檔的 `updatedAt` 都是同一個值）。
    /// 實測刪掉 `|| old.updatedAt < s.updatedAt`，15/15 全綠。
    @Test("已確認後又發生新一輪同類結果（時戳前進）—— 不得被當成已看過而靜默吞掉")
    func newerTimestampRevokesAck() {
        var r = SessionRegistry()
        r.upsert(state("a", .error))            // 第一次失敗，session 還活著
        _ = r.acknowledgeAll()                  // 使用者開了面板，看過了
        #expect(r.isAcknowledged("a"))

        // 第二次失敗（同樣分類為 .error）之後 session 結束。
        // 時戳前進是「這是新結果」的唯一訊號 —— activity 值一模一樣。
        r.upsert(state("a", .error, live: false, at: 1_788_628_050))
        #expect(r.visible.map(\.id) == ["a"], """
            新一輪的 error 必須重新變成未確認。
            少了 `|| old.updatedAt < s.updatedAt`，第二次失敗會被當成「已看過又已結束」
            直接從表中清掉 —— 使用者永遠不會知道它發生過。
            """)
    }

    /// `upsert` 的「已看過又已結束 → 立即清掉」分支（與 `newerTimestampRevokesAck`
    /// 是同一段程式碼的另一半：那裡時戳前進所以**留下**，這裡時戳不變所以**清掉**）。
    ///
    /// 這個分支曾經從未被觸及。實測整段刪掉，15/15 全綠 —— 後果是 `states`
    /// 單調累積殘留 entry（`visible` 有自己的過濾所以畫面正常，但記憶體會漏）。
    @Test("已確認的 session 之後結束（時戳不變）—— 立即從表中清除")
    func endedAfterAckRemovedImmediately() {
        var r = SessionRegistry()
        r.upsert(state("a", .done))
        _ = r.acknowledgeAll()
        r.upsert(state("a", .done, live: false))     // 同時戳 → 不撤銷確認
        #expect(r.states["a"] == nil, "已看過又已結束 → 立即清掉，不等下一次 acknowledgeAll")
    }

    // MARK: - acknowledged 的回收（最終 review 的 C1）

    /// `acknowledged` 必須跟著 `states` 一起回收。
    ///
    /// 只清 `states` 會讓 id 永遠留在 `acknowledged` 裡 —— `refreshLiveness` 只走訪
    /// `states.keys`，所以它再也不會被 `remove(_:)` 掃到。
    @Test("acknowledgeAll 移除已結束的 session 時，acknowledged 也要清掉")
    func acknowledgeAllReclaimsAcknowledged() {
        var r = SessionRegistry()
        r.upsert(state("a", .done, live: false))
        _ = r.acknowledgeAll()
        #expect(r.states["a"] == nil)
        #expect(!r.isAcknowledged("a"), "states 清了但 acknowledged 留著 —— 這就是洩漏")
    }

    @Test("upsert 的立即清除路徑，acknowledged 也要清掉")
    func inlineRemovalReclaimsAcknowledged() {
        var r = SessionRegistry()
        r.upsert(state("a", .done))          // 活著
        _ = r.acknowledgeAll()               // 看過了（活著，所以留在 states）
        #expect(r.isAcknowledged("a"))
        r.upsert(state("a", .done, live: false))   // 同時戳結束 → 立即清除
        #expect(r.states["a"] == nil)
        #expect(!r.isAcknowledged("a"), "states 清了但 acknowledged 留著 —— 這就是洩漏")
    }

    /// **回訪 session 的新結果不得被靜默吞掉。**
    ///
    /// `claude --resume` 會沿用同一個 session_id。若上一輪已被 ack 並移出 `states`，
    /// 而 `acknowledged` 還留著，那麼這一輪的**第一個**被觀察到的 snapshot 若已是
    /// `.ended`（事件被 FSEvents 合併、或 crash 得很快），`upsert` 會直接刪掉它 ——
    /// 而且救不回來，因為撤銷確認的分支需要 `states[id]` 非 nil。
    /// 整夜 pipeline 失敗、早上看過、下午 resume 又失敗 → **紅燈從來沒亮過**。
    @Test("回訪的 session 若一開始就是已結束，結果仍必須被看見")
    func revisitedSessionResultIsNotSwallowed() {
        var r = SessionRegistry()
        r.upsert(state("a", .error))         // 第一輪，活著
        _ = r.acknowledgeAll()               // 使用者看過
        r.upsert(state("a", .error, live: false))   // 第一輪結束 → 立即清除

        // 第二輪（resume 同一個 id），只觀察到最終的已結束檔
        r.upsert(state("a", .error, live: false, at: 1_788_700_000))
        #expect(r.visible.map(\.id) == ["a"], """
            回訪 session 的新結果被吞掉了。
            acknowledged 沒有跟著 states 一起回收，於是這個 id 永遠帶著「已看過」的標記。
            """)
    }
}
