import Testing
import Foundation
@testable import AuraCore
@testable import AuraHookFile

@Suite("PipelineGraph composition root", .serialized)
struct CompositionRootTests {

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-graph-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("production() 的每個依賴都真的接上，沒有 nil")
    func productionGraphIsWired() {
        let g = PipelineGraph.production(root: try! makeRoot())
        #expect(g.source is HookFileSource, "production 必須用真的檔案來源")
        #expect(g.liveness is SysctlLiveness, "production 必須用真的 pid 探測，不是 stub")
        #expect(g.policy is PriorityAggregatePolicy)
    }

    @Test("start() 會消耗 bootstrap 的結果並更新 iconState")
    func startConsumesBootstrap() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "boot1", root: root) { _ in
            var s = SessionSnapshot(sessionID: "boot1")
            s.mainActivity = .error; s.terminated = true; s.writtenAt = Date()
            return s
        }
        let g = PipelineGraph.production(root: root)
        g.start()
        defer { g.stop() }
        #expect(g.iconState.activity == .error,
                "app 沒開時累積的未確認 error，啟動後必須立刻反映在 icon 上")
    }

    @Test("onIconStateChange callback 真的被呼叫（spy 斷言，不接受被 catch-all 吞掉）")
    func callbackIsInvoked() throws {
        let root = try makeRoot()
        let g = PipelineGraph.production(root: root)
        var received: [IconState] = []
        g.onIconStateChange = { received.append($0) }

        try SnapshotIO.update(sessionID: "cb1", root: root) { _ in
            var s = SessionSnapshot(sessionID: "cb1"); s.mainActivity = .waiting
            s.pid = getpid(); s.pidStartedAt = SysctlLiveness().startTime(ofPID: getpid())
            s.writtenAt = Date(); return s
        }
        g.start()
        defer { g.stop() }
        #expect(!received.isEmpty, "start() 必須觸發至少一次 icon 更新")
        #expect(received.last?.activity == .waiting)
    }

    @Test("acknowledgeAll 會刪除已結束且已確認的狀態檔")
    func acknowledgeDeletesFiles() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "ack1", root: root) { _ in
            var s = SessionSnapshot(sessionID: "ack1")
            s.mainActivity = .done; s.terminated = true; s.writtenAt = Date(); return s
        }
        let g = PipelineGraph.production(root: root)
        g.start(); defer { g.stop() }
        #expect(g.iconState.activity == .done)

        g.acknowledgeAll()
        // 這條原本直接斷言，2026-09-17 全量時紅過（量到 `.done`）——就是追了一整天的那個
        // flake。根因是 `start()` 排出去的 FSEvents 回呼可能在 `acknowledgeAll()` **之後**
        // 才送達，用刪檔前的內容把 iconState 蓋回 `.done`。燈號的契約本來就是最終一致
        // （FSEvents 驅動），所以改成有界輪詢：**斷言一字未改**，只是不再假設它同步完成。
        // 真的壞掉時仍然會紅，只是要等滿 10 秒。2 秒在全量並行下不夠（2026-09-17 又紅一次，
        // 剛好卡在 2.006 秒）——FSEvents 的送達延遲本來就受機器負載影響。
        let deadline = Date().addingTimeInterval(10)
        while g.iconState.activity != .idle && Date() < deadline { usleep(5_000) }
        #expect(g.iconState.activity == .idle, "確認後尾巴清空，燈回正常")
        #expect(SnapshotIO.allSessionIDs(root: root).isEmpty, "已結束且已確認 → 檔案刪除")
    }

    @Test("狀態檔被外部刪除後，refreshLiveness 移除該 session")
    func refreshLivenessDropsDeletedFiles() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "gone1", root: root) { _ in
            var s = SessionSnapshot(sessionID: "gone1")
            s.mainActivity = .waiting
            s.pid = getpid(); s.pidStartedAt = SysctlLiveness().startTime(ofPID: getpid())
            s.writtenAt = Date(); return s
        }
        let g = PipelineGraph.production(root: root)
        g.start(); defer { g.stop() }
        #expect(g.iconState.activity == .waiting)

        // 模擬使用者手動清理：rm ~/.agentaura/sessions/*
        try SnapshotIO.delete(sessionID: "gone1", root: root)
        g.refreshLiveness()
        #expect(g.iconState.activity == .idle, "檔案消失 → 不得留下幽靈 session")
    }

    @Test("狀態目錄被整個刪除後，refreshLiveness 重建它")
    func refreshLivenessRecreatesRoot() throws {
        let root = try makeRoot()
        let g = PipelineGraph.production(root: root)
        g.start(); defer { g.stop() }
        try FileManager.default.removeItem(at: root)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        g.refreshLiveness()
        #expect(FileManager.default.fileExists(atPath: root.path),
                "目錄不存在會讓後續 hook 寫入失敗（aura-hook 會靜默放棄）")
    }

    @Test("refreshLiveness 會把 pid 已死的 working session 移出")
    func refreshLivenessDropsDeadSessions() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "dead1", root: root) { _ in
            var s = SessionSnapshot(sessionID: "dead1")
            s.mainActivity = .working
            s.pid = 999_999; s.pidStartedAt = 12_345      // 不存在的 pid
            s.writtenAt = Date(); return s
        }
        let g = PipelineGraph.production(root: root)
        g.start(); defer { g.stop() }
        g.refreshLiveness()
        #expect(g.iconState.activity == .idle,
                "terminal 被強制關掉、SessionEnd 沒來 → 不得永遠卡 working")
    }

    /// **解析失敗 ≠ 檔案不存在**（spec §3.3 / §4 第 3 列）。
    ///
    /// `aura-hook` 若在 `truncate(0)` 與 `write` 之間被 SIGKILL（睡眠、OOM、
    /// 強制關 terminal），磁碟上會留下**永久損壞**的檔。若 `refreshLiveness`
    /// 把它當成「檔案不存在」而移除 session，一個**真的在等你批准**的
    /// session 就會從面板消失 —— 而使用者還沒回答，不會再有任何 hook 事件
    /// 把它重建回來（§2.4.1 實測：按 Deny 不產生事件）。橘燈永久熄滅。
    @Test("狀態檔損壞時保留上次已知狀態，不得當成 session 不存在")
    func refreshLivenessKeepsStateOnParseFailure() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "wait1", root: root) { _ in
            var s = SessionSnapshot(sessionID: "wait1")
            s.mainActivity = .waiting
            s.pid = getpid(); s.pidStartedAt = SysctlLiveness().startTime(ofPID: getpid())
            s.writtenAt = Date(); return s
        }
        let g = PipelineGraph.production(root: root)
        g.start(); defer { g.stop() }
        #expect(g.iconState.activity == .waiting)

        // 模擬被 SIGKILL 打斷的寫入：檔案還在，但內容是半截的
        let url = try SnapshotIO.url(for: "wait1", root: root)
        let full = try Data(contentsOf: url)
        try full.prefix(full.count / 2).write(to: url)
        #expect(SnapshotIO.read(sessionID: "wait1", root: root) == nil, "前提：損壞檔應讀不出來")

        g.refreshLiveness()
        #expect(g.iconState.activity == .waiting, """
            損壞的檔被當成「session 不存在」而移除了。
            spec §3.3 / §4 第 3 列：解析失敗時保留上一次已知狀態並重試，
            絕不當成 session 不存在。使用者還在等你批准，而橘燈熄了。
            """)
    }

    /// 對照組：檔案**真的**不存在時仍然要移除（否則會留下幽靈 session）。
    @Test("檔案真的不存在時仍然移除 —— 兩種情況必須分開")
    func refreshLivenessStillRemovesMissingFiles() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "gone2", root: root) { _ in
            var s = SessionSnapshot(sessionID: "gone2")
            s.mainActivity = .waiting
            s.pid = getpid(); s.pidStartedAt = SysctlLiveness().startTime(ofPID: getpid())
            s.writtenAt = Date(); return s
        }
        let g = PipelineGraph.production(root: root)
        g.start(); defer { g.stop() }
        #expect(g.iconState.activity == .waiting)

        try SnapshotIO.delete(sessionID: "gone2", root: root)
        g.refreshLiveness()
        #expect(g.iconState.activity == .idle, "檔案消失 → 不得留下幽靈 session")
    }

    /// A2（/simplify 波次1，eff#2）：`refreshLiveness` 用 `st_mtimespec` 當閘門——mtime
    /// 沒變就跳過 `SnapshotIO.read`，沿用上一輪讀到的內容，只重算 liveness。
    ///
    /// 正常情況下任何寫入都會動 mtime、FSEvents 會送真事件，這裡刻意用 `utimensat`
    /// 把第二次寫入的 mtime **強制改回**跟第一次一樣（模擬「mtime 這個代理訊號剛好沒變」
    /// 的邊界情況），藉此觀察閘門是不是真的生效：mtime 沒變時，即使磁碟上的實際內容
    /// 已經換成 `.error`，`iconState` 仍該停在上一輪讀到的 `.waiting`。
    @Test("mtime 沒變時沿用上一輪讀到的內容，不重新讀取解析（效能閘門）")
    func refreshLivenessSkipsRereadWhenMtimeUnchanged() throws {
        let root = try makeRoot()
        let url = try SnapshotIO.url(for: "stale1", root: root)
        try SnapshotIO.update(sessionID: "stale1", root: root) { _ in
            var s = SessionSnapshot(sessionID: "stale1")
            s.mainActivity = .waiting
            s.pid = getpid(); s.pidStartedAt = SysctlLiveness().startTime(ofPID: getpid())
            s.writtenAt = Date(); return s
        }
        let g = PipelineGraph.production(root: root)
        g.start(); defer { g.stop() }
        #expect(g.iconState.activity == .waiting)

        g.refreshLiveness()   // 建立 lastSeen 快取（讀到 waiting）
        #expect(g.iconState.activity == .waiting)

        var before = stat()
        #expect(stat(url.path, &before) == 0, "前提：檔案應該已經存在")

        try SnapshotIO.update(sessionID: "stale1", root: root) { existing in
            var s = existing ?? SessionSnapshot(sessionID: "stale1")
            s.mainActivity = .error
            return s
        }
        // 強制把 mtime 改回寫入前的那個值——模擬「mtime 剛好沒變」。
        var times: [timespec] = [before.st_atimespec, before.st_mtimespec]
        #expect(utimensat(AT_FDCWD, url.path, &times, 0) == 0, "utimensat 沒成功，mtime 沒被強制改回去，這條測試的前提就不成立")

        g.refreshLiveness()
        #expect(g.iconState.activity == .waiting, """
            mtime 沒變（刻意用 utimensat 模擬）時 refreshLiveness 應該沿用上一輪讀到的
            內容（waiting），不該因為磁碟上的新內容（error）而改變——這正是 mtime 閘門
            的效果：跳過 SnapshotIO.read，只重算 liveness。
            """)
    }
}
