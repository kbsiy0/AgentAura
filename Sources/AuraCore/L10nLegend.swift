/// T27：`LegendModel.label(_:)` 的五個窮盡值搬進字串表。
/// T29：加 `explanation`（ⓘ 固定提示句）＋ `changeColorTooltip`（帶參數的色點 tooltip／
/// accessibility label，兩處共用同一句，見 `LegendRowView.swift`）——沿用同一個「圖例」
/// 領域，不另開檔案。
public enum L10nLegend: L10nCatalog, Sendable {
    case error, waiting, working, done
    /// T15：ⓘ 圖示的 `.help` 固定提示句——面板底部提示行拿掉後唯一還留著的解釋文字。
    case explanation

    public func text(_ language: Language) -> String {
        switch self {
        case .error:
            switch language {
            case .english: return "Error"
            case .traditionalChinese: return "錯誤"
            }
        case .waiting:
            switch language {
            case .english: return "Waiting"
            case .traditionalChinese: return "等你"
            }
        case .working:
            switch language {
            case .english: return "Running"
            case .traditionalChinese: return "執行中"
            }
        case .done:
            switch language {
            case .english: return "Done"
            case .traditionalChinese: return "已完成"
            }
        case .explanation:
            // "lights" 與 "dot" **刻意是兩個詞**，不是沒對齊：前者指選單列上那八顆 LED
            // （`LEDStripView`），後者指圖例列裡可以點來改色的圓點（`LegendRowView`）——
            // 兩個不同的東西，中文原文也分別用「燈」與「色點」。統一成一個詞會讓句子變錯。
            switch language {
            case .english: return "All eight lights together represent every session · tap a dot to change its color"
            case .traditionalChinese: return "八顆燈一起代表全部 session · 點色點改顏色"
            }
        }
    }

    /// `LegendRowView` 的 `.help`／`.accessibilityLabel` 共用同一句——換色按鈕的說明，
    /// 帶參數（該項目的標籤，例如「等你」／"Waiting"）。
    public static func changeColorTooltip(label: String, language: Language) -> String {
        switch language {
        case .english: return "Change the color for \"\(label)\""
        case .traditionalChinese: return "改「\(label)」的顏色"
        }
    }
}
