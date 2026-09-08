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

    public private(set) var registry = SessionRegistry()
    public var onIconStateChange: ((IconState) -> Void)?

    private var consumeTask: Task<Void, Never>?
    private let lock = NSLock()

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
        consumeTask = Task { [weak self] in
            guard let self else { return }
            for await snap in self.source.snapshots {
                self.ingest(snap)
                self.notifyChange()
            }
        }
    }

    public func stop() {
        consumeTask?.cancel(); consumeTask = nil
        source.stop()
    }

    /// 面板開啟：確認全部，並刪除已結束且已確認的狀態檔。
    public func acknowledgeAll() {
        lock.lock()
        let removable = registry.acknowledgeAll()
        lock.unlock()
        for id in removable {
            // 刪檔失敗不可影響其他工作（user CLAUDE.md #8：收尾動作各自 try/except）
            try? SnapshotIO.delete(sessionID: id, root: root)
        }
        notifyChange()
    }

    /// 重新驗證所有 session 的 pid —— 抓「terminal 被強制關掉，SessionEnd 沒來」。
    public func refreshLiveness() {
        lock.lock()
        let ids = Array(registry.states.keys)
        lock.unlock()
        // 目錄若被整個刪掉（例如使用者手動清理），重建它 —— 否則後續 hook 寫入會失敗。
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for id in ids {
            guard let snap = SnapshotIO.read(sessionID: id, root: root) else {
                // 檔案已不存在。檔案是狀態的唯一真實來源，沒有檔案就沒有 session。
                // 若該 session 其實還活著，下一個 hook 事件會重建它。
                // 不處理這條會讓外部刪檔（rm ~/.agentaura/sessions/*）後
                // 面板永遠顯示那些幽靈 session。
                lock.lock(); registry.remove(id); lock.unlock()
                continue
            }
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
