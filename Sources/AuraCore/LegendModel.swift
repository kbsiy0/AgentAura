/// 圖例列的呈現資料（R7 常駐圖例）。spec §2／§3：`items(for:)` 的順序 = `Activity.customizable`。
public struct LegendItem: Equatable, Sendable, Identifiable {
    public let activity: Activity
    public let label: String
    public let color: RGBA
    public var id: Activity { activity }
}

public enum LegendModel {
    /// 順序＝`Activity.customizable`；每項的 label／色分別取自 `label(_:)`／`palette`。
    public static func items(for palette: IconPalette) -> [LegendItem] {
        Activity.customizable.map { activity in
            LegendItem(activity: activity, label: label(activity), color: palette[activity])
        }
    }

    /// 窮盡 switch，供 `items(for:)` 內部使用。D-c 的具體字串。
    static func label(_ activity: Activity) -> String {
        switch activity {
        case .error:   return "錯誤"
        case .waiting: return "等你"
        case .working: return "執行中"
        case .done:    return "已完成"
        case .idle:    return ""
        }
    }
}

extension IconPalette {
    /// 逐欄位替換：只有 `activity` 對應的欄位變成 `color`，其餘不動。
    public func with(_ activity: Activity, color: RGBA) -> IconPalette {
        switch activity {
        case .idle:    return IconPalette(idle: color, working: working, done: done, waiting: waiting, error: error)
        case .working: return IconPalette(idle: idle, working: color, done: done, waiting: waiting, error: error)
        case .done:    return IconPalette(idle: idle, working: working, done: color, waiting: waiting, error: error)
        case .waiting: return IconPalette(idle: idle, working: working, done: done, waiting: color, error: error)
        case .error:   return IconPalette(idle: idle, working: working, done: done, waiting: waiting, error: color)
        }
    }

    /// 與 `.default` 逐欄位相等。
    public var isDefault: Bool { self == .default }
}
