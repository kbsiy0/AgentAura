import Foundation

public protocol AggregatePolicy: Sendable {
    func aggregate(_ states: [SessionState]) -> IconState
}

/// D1：`error > waiting > working > done > idle`。
///
/// 純函數，與寫入順序、session 先後完全無關 —— 優先序完全來自 `Activity.priority`。
/// 若要調整優先序，改 `Activity.priority`，不要改這裡。
public struct PriorityAggregatePolicy: AggregatePolicy {
    public init() {}

    public func aggregate(_ states: [SessionState]) -> IconState {
        guard !states.isEmpty else { return .empty }

        var counts: [Activity: Int] = [:]
        var top = Activity.idle
        var live = 0

        for s in states {
            counts[s.activity, default: 0] += 1
            top = max(top, s.activity)
            if s.liveness != .ended { live += 1 }
        }
        return IconState(activity: top, counts: counts, liveCount: live)
    }
}
