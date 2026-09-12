import Foundation
import AuraCore

/// A3（/simplify 波次1，eff#1）：完全可控的 `EventSource` double，讓 `PipelineGraph` 的
/// 批次合併邏輯可以脫離真的 FSEvents 排程時間，直接餵一批 snapshot 進去測。
final class FakeEventSource: EventSource, @unchecked Sendable {
    private var continuation: AsyncStream<[SessionSnapshot]>.Continuation?
    let snapshots: AsyncStream<[SessionSnapshot]>
    private let bootstrapSnapshots: [SessionSnapshot]
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    init(bootstrap: [SessionSnapshot] = []) {
        self.bootstrapSnapshots = bootstrap
        var cont: AsyncStream<[SessionSnapshot]>.Continuation!
        self.snapshots = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    func bootstrap() -> [SessionSnapshot] { bootstrapSnapshots }
    func start() { startCallCount += 1 }
    func stop() { stopCallCount += 1; continuation?.finish() }

    /// 測試專用：一次塞進一整批（模擬「一個 FSEvents 批次有 K 個檔案變動」）。
    func push(_ batch: [SessionSnapshot]) { continuation?.yield(batch) }
}
