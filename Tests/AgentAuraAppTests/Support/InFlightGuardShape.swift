import Foundation

/// T01 必辦⑤（前半）：`inFlight` 合流 guard 的形狀，供 T07 的
/// `HookVerificationStore` 直接沿用（spec §3.1：「已經有一個在跑就不開第二個」）。
///
/// 形狀借 `PipelineGraph.consumeTask` 的單一 task handle 與
/// `ColorPickerCoordinator.activeActivity` 的 in-flight guard——因為住在
/// `@MainActor`，「檢查與設定」天然原子、不需要額外的鎖。`inFlight != nil`
/// **正好就是** `Verification.inFlight` 的訊號：序列化與「檢查中…」文案的
/// 誠實性是同一個機制，不是兩件事（R2）。
@MainActor
final class InFlightGuardShape {
    private(set) var inFlight: Task<Void, Never>?
    private(set) var startedCount = 0
    private(set) var skippedCount = 0

    /// 啟動一段背景工作；已經有一個在跑就跳過（回 `false`）。
    @discardableResult
    func begin(_ work: @escaping () async -> Void) -> Bool {
        guard inFlight == nil else { skippedCount += 1; return false }
        startedCount += 1
        inFlight = Task { [weak self] in
            await work()
            self?.inFlight = nil
        }
        return true
    }
}

/// 可控制何時完成的非同步柵欄，供測試精準卡住 `InFlightGuardShape.begin` 裡的
/// 背景工作，觀察「還在跑」與「跑完了」兩個時刻。
actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
