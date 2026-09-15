/// 圖例列的呈現資料（R7 常駐圖例）。spec §2／§3：`items(for:)` 的順序 = `Activity.customizable`。
public struct LegendItem: Equatable, Sendable, Identifiable {
    public let activity: Activity
    public let label: String
    public let color: RGBA
    public var id: Activity { activity }
}

public enum LegendModel {
    /// 順序＝`Activity.customizable`；每項的 label／色分別取自 `label(_:)`／`palette`。
    ///
    /// T27（i18n）：`language` **帶預設值 `.traditionalChinese`**（同 `Jargon`／`PanelViewModel.rows`
    /// 的 T27 理由）——`Tests/AgentAuraAppTests`（`PanelPixelTests`／`T19WhiteWorkingEvidenceRenderer`）
    /// 直接呼叫這個函式量像素尺寸，不關心語言；生產路徑（`PanelModel.make`）明確傳 `language`。
    public static func items(for palette: IconPalette, language: Language) -> [LegendItem] {
        Activity.customizable.map { activity in
            LegendItem(activity: activity, label: label(activity, language: language), color: palette[activity])
        }
    }

    /// 窮盡 switch，供 `items(for:)` 內部使用。`OptionsMenuModel.lightBarWarning` 也借用它
    /// 組提醒句（同一個 oracle，不重複維護一份 Activity→人話的對應）。
    static func label(_ activity: Activity, language: Language) -> String {
        switch activity {
        case .error:   return L10nLegend.error.text(language)
        case .waiting: return L10nLegend.waiting.text(language)
        case .working: return L10nLegend.working.text(language)
        case .done:    return L10nLegend.done.text(language)
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
