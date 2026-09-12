import Foundation
import AuraCore

/// Composition root（無 UI 部分）。
///
/// **唯一的組裝點。** 每個依賴都必須在此接上，並由 CompositionRootTests 用
/// spy 斷言真的被呼叫 —— 單元測試證明「能用」，這裡證明「有用」。
public final class PipelineGraph: @unchecked Sendable {

    public let liveness: LivenessProbing
    public let policy: AggregatePolicy
    public let source: EventSource
    public let root: URL

    /// **刻意不是 `public`。**
    ///
    /// 所有寫入都在 `lock` 下，但一個 `public` 的裸屬性讓外部可以**繞過 lock 直接讀**，
    /// 與 `ingest()` 的鎖內寫入形成未同步的並發存取 —— `@unchecked Sendable` 的承諾
    /// 就只兌現了一半。實證：面板的 `refreshPanel()` 原本寫 `graph.registry.visible`，
    /// 正是這種讀取。收成 `internal` 之後，App target（只 `import AuraHookFile`）
    /// 拿不到它，被迫走下面那個上鎖的 `visibleSessions`；測試用 `@testable` 仍可存取。
    private(set) var registry = SessionRegistry()

    /// 面板要列的 session。**上鎖**讀取 —— 這是外部取得 registry 內容的唯一途徑。
    public var visibleSessions: [SessionState] {
        lock.lock(); defer { lock.unlock() }
        return registry.visible
    }
    public var onIconStateChange: ((IconState) -> Void)?

    private var consumeTask: Task<Void, Never>?
    private let lock = NSLock()

    /// A2（/simplify 波次1，eff#2）：`refreshLiveness` 上次成功讀到的 `(mtime, snapshot)`，
    /// 讓下一輪能用 `st_mtimespec` 當閘門——mtime 沒變就跳過 `SnapshotIO.read`（55 µs／檔
    /// 的 read+decode），只重算 liveness（sysctl，~5 µs）。**只在成功讀到時更新**：
    /// 解析失敗那個分支故意不寫這裡，讓下一輪的 mtime 比對必然不相符、繼續重試
    /// （保留「解析失敗要保留上次已知狀態並重試」這條 invariant，見下方 `refreshLiveness`）。
    private var lastSeen: [String: (mtime: FileStamp, snapshot: SessionSnapshot)] = [:]

    private struct FileStamp: Equatable { let sec: Int; let nsec: Int }

    public init(root: URL, liveness: LivenessProbing, policy: AggregatePolicy, source: EventSource) {
        self.root = root; self.liveness = liveness; self.policy = policy; self.source = source
    }

    public var iconState: IconState {
        lock.lock(); defer { lock.unlock() }
        return policy.aggregate(registry.visible)
    }

    public func start() {
        source.start()
        for snap in source.bootstrap() { ingest(snap) }
        notifyChange()
        // A3（/simplify 波次1，eff#1）：一批 K 個 snapshot 全部 ingest 完才 notifyChange()
        // 一次——跟上面 bootstrap 的形狀一致。`source.snapshots` 現在本來就是逐批吐
        // （見 `HookFileSource.emit`），這裡只是照那個形狀消費，不必自己在消費端做
        // 危險的「非阻塞排乾緩衝區」。
        consumeTask = Task { [weak self] in
            guard let self else { return }
            for await batch in self.source.snapshots {
                for snap in batch { self.ingest(snap) }
                self.notifyChange()
            }
        }
    }

    public func stop() {
        consumeTask?.cancel(); consumeTask = nil
        source.stop()
    }

    /// 面板**關閉**（`NSPopover` didClose）：確認全部，並刪除已結束且已確認的狀態檔。開啟路徑不得呼叫（S1-3）。
    public func acknowledgeAll() {
        lock.lock()
        let removable = registry.acknowledgeAll()
        lock.unlock()
        for id in removable {
            // 刪檔失敗不可影響其他工作（user CLAUDE.md #8：收尾動作各自 try/except）
            try? SnapshotIO.delete(sessionID: id, root: root)
            lastSeen[id] = nil   // A2：檔案已刪，別留著孤兒快取
        }
        notifyChange()
    }

    /// 重新驗證所有 session 的 pid —— 抓「terminal 被強制關掉，SessionEnd 沒來」。
    ///
    /// A2（/simplify 波次1，eff#2）：這個函式的目的只是「重驗 pid」，兩次 tick 之間
    /// 檔案內容通常沒變（變了 FSEvents 會送）——`stat` 拿 mtime 當閘門，mtime 沒變就
    /// 跳過 `SnapshotIO.read`（55 µs／檔），只重算 liveness（sysctl，~5 µs），約 10×
    /// 降幅。**這三條 invariant 不因這個優化而改變**：
    /// 1. **檔案消失 ≠ 解析失敗**：只有 `stat` 失敗（檔案真的不存在）才 `registry.remove`；
    ///    `SnapshotIO.read` 讀失敗（半截 JSON）時保留舊狀態，不移除、不更新 `lastSeen`。
    /// 2. **解析失敗要保留上次已知狀態並重試**：`lastSeen` 只在讀成功時更新，讀失敗那
    ///    一輪之後 mtime 比對必然不相符（除非 mtime 剛好沒變又剛好讀失敗——那種情況下
    ///    行為等同「跳過重讀」，仍不移除、仍保留舊狀態，語意沒有變壞），下一輪會再試。
    /// 3. **只有檔案真的消失才移除 session**：`stat` 這裡取代了原本的 `fileExists` 檢查，
    ///    同一顆語意（is-the-file-there），但少一次多餘的 `url(for:)`＋`stat`。
    public func refreshLiveness() {
        lock.lock()
        let ids = Array(registry.states.keys)
        lock.unlock()
        // 目錄若被整個刪掉（例如使用者手動清理），重建它 —— 否則後續 hook 寫入會失敗。
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for id in ids {
            guard let url = try? SnapshotIO.url(for: id, root: root) else {
                lock.lock(); registry.remove(id); lock.unlock()
                lastSeen[id] = nil
                continue
            }
            var st = stat()
            guard stat(url.path, &st) == 0 else {
                // 檔案真的不存在——唯一允許 `registry.remove` 的分支。
                lock.lock(); registry.remove(id); lock.unlock()
                lastSeen[id] = nil
                continue
            }
            let mtime = FileStamp(sec: Int(st.st_mtimespec.tv_sec), nsec: Int(st.st_mtimespec.tv_nsec))

            if let cached = lastSeen[id], cached.mtime == mtime {
                // 內容沒變：跳過 read/decode，只用上次讀到的內容重算一次 liveness。
                ingest(cached.snapshot)
                continue
            }

            // **解析失敗與檔案不存在必須分開。**
            //
            // `SnapshotIO.read` 對「檔案不存在」與「內容解析失敗」回同一個 nil
            // （`garbageFileReturnsNil` / `truncatedFileReturnsNil` 正是在釘死後者）——
            // 但上面已經用 `stat` 確認過檔案存在，這裡回 nil 只可能是解析失敗。
            // spec §3.3 / §4 第 3 列：「解析失敗時保留上一次已知狀態並重試，
            // **絕不當成 session 不存在**」。`aura-hook` 若在 truncate 與 write 之間被
            // SIGKILL，磁碟上留下永久損壞的檔，5 秒後這裡就會把一個**真的在等你
            // 批准**的 session 移除，而使用者還沒回答 → 不會再有事件重建它 →
            // 橘燈永久熄滅。
            guard let snap = SnapshotIO.read(sessionID: id, root: root) else {
                continue   // 保留舊狀態，下一輪重試；刻意不更新 lastSeen（見上方文件第 2 點）
            }
            lastSeen[id] = (mtime, snap)
            ingest(snap)
        }
        notifyChange()
    }

    private func ingest(_ snap: SessionSnapshot) {
        let state = SessionReducer.state(from: snap, liveness: liveness)
        lock.lock(); registry.upsert(state); lock.unlock()
    }

    private func notifyChange() { onIconStateChange?(iconState) }

    /// production 組裝：每個依賴都是真的實作，沒有測試替身。
    public static func production(root: URL = SnapshotIO.defaultRoot) -> PipelineGraph {
        PipelineGraph(root: root,
                      liveness: SysctlLiveness(),
                      policy: PriorityAggregatePolicy(),
                      source: HookFileSource(root: root))
    }
}
