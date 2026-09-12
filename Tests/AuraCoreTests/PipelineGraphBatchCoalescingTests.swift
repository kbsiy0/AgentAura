import Testing
import Foundation
@testable import AuraCore
@testable import AuraHookFile

/// A3（/simplify 波次1，eff#1）：一個底層事件批次裡有 K 個 session 變動時，
/// `PipelineGraph.start()` 的消費迴圈只該呼叫一次 `onIconStateChange`——批次內全部
/// `ingest` 完才通知，不是每個 session 各自通知一次（下游一次通知 = `registry.visible`
/// ×3 + `PanelModel.make` 全 row 字串重建 + Timer 拆建 + SwiftUI rootView 指派，
/// 見 simplify-efficiency.md #1）。用 `FakeEventSource` 直接控制批次形狀，
/// 不依賴真的 FSEvents 排程時間（那會抖動）。
/// `onIconStateChange` 從 FSEvents 背景 queue 上來（見 `PipelineGraph.registry` 的文件），
/// 跨執行緒累積收到的值要上鎖，不能是裸的 `var [IconState]`（Swift 6 strict concurrency
/// 也會直接擋這種跨執行緒可變捕捉）。
final class ReceivedIconStates: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [IconState] = []
    func append(_ s: IconState) { lock.lock(); items.append(s); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return items.count }
    var last: IconState? { lock.lock(); defer { lock.unlock() }; return items.last }
}

@Suite("PipelineGraph 批次合併（A3）")
struct PipelineGraphBatchCoalescingTests {

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-batch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// pid／pidStartedAt 給真的當前行程——沒有這兩個欄位 `SessionReducer` 會判定
    /// `.ended`（見 `resolveLiveness`），這裡要測的是「三個都被 ingest」，跟既有
    /// `CompositionRootTests` 同樣的手法讓它們保持「活著」。
    func snap(_ id: String, _ activity: Activity) -> SessionSnapshot {
        var s = SessionSnapshot(sessionID: id)
        s.mainActivity = activity
        s.pid = getpid()
        s.pidStartedAt = SysctlLiveness().startTime(ofPID: getpid())
        s.writtenAt = Date()
        return s
    }

    static func waitUntil(timeout: TimeInterval, _ condition: @Sendable () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                Issue.record("等待逾時（\(timeout)s）")
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @Test("一批 3 個 session 變動只觸發一次 onIconStateChange")
    func oneNotifyPerBatch() async throws {
        let source = FakeEventSource()
        let g = PipelineGraph(root: try makeRoot(), liveness: SysctlLiveness(),
                              policy: PriorityAggregatePolicy(), source: source)
        let received = ReceivedIconStates()
        g.onIconStateChange = { received.append($0) }
        g.start()          // bootstrap 是空的，但 start() 本身無條件 notifyChange() 一次
        defer { g.stop() }
        let baseline = received.count

        source.push([snap("k1", .working), snap("k2", .waiting), snap("k3", .error)])
        await Self.waitUntil(timeout: 2) { received.count > baseline }

        #expect(received.count == baseline + 1, """
            一批 3 個 session 變動觸發了 \(received.count - baseline) 次 onIconStateChange，
            預期只有 1 次——批次內應該全部 ingest 完才通知一次。
            """)
        #expect(g.iconState.activity == .error, "三個都已經 ingest，聚合應該反映最高優先序（error）")
        #expect(g.visibleSessions.count == 3)
    }

    @Test("兩個各自獨立的批次各觸發一次通知")
    func twoBatchesNotifyTwiceEach() async throws {
        let source = FakeEventSource()
        let g = PipelineGraph(root: try makeRoot(), liveness: SysctlLiveness(),
                              policy: PriorityAggregatePolicy(), source: source)
        let received = ReceivedIconStates()
        g.onIconStateChange = { received.append($0) }
        g.start()
        defer { g.stop() }
        let baseline = received.count

        source.push([snap("a1", .working)])
        await Self.waitUntil(timeout: 2) { received.count >= baseline + 1 }
        source.push([snap("a2", .waiting)])
        await Self.waitUntil(timeout: 2) { received.count >= baseline + 2 }

        #expect(received.count == baseline + 2, "兩個獨立批次應各觸發一次，合計 2 次")
    }
}
