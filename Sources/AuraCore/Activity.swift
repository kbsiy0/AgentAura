/// Session 的活動狀態。
///
/// `priority` 是 D1 聚合優先序的**唯一來源**：`error > waiting > working > done > idle`。
/// 改動此處會同時改變 icon 聚合結果與面板排序 —— 兩者都有對應的 mutation 驗證。
public enum Activity: String, Codable, Sendable, CaseIterable {
    case idle
    case done
    case working
    case waiting
    case error

    /// 數字越大越優先。
    public var priority: Int {
        switch self {
        case .idle:    0
        case .done:    1
        case .working: 2
        case .waiting: 3
        case .error:   4
        }
    }

    /// 靜止態：使用者行動前不會再有新事件覆寫。
    ///
    /// `MergeRules` 用它決定是否忽略 subagent 事件 —— 主 agent 靜止時，
    /// 殘留的 subagent 活動（含 Claude Code 的內部 subagent）不得改變 activity（§2.5.1）。
    public var isQuiescent: Bool {
        self == .waiting || self == .done || self == .error
    }
}

extension Activity: Comparable {
    public static func < (lhs: Activity, rhs: Activity) -> Bool {
        lhs.priority < rhs.priority
    }
}
