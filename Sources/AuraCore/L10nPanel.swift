/// T26 示範：`PanelModel.emptyRowsMessage` 從寫死的中文字面搬進字串表（D-1 示範 3/3，
/// 純靜態、非 Options 列標題）。`PanelModel` 其餘欄位（`title` 走 `install.healthLabel`／
/// `PanelViewModel` 等）暫時仍是寫死的中文，見 `L10nStrayLiteralSourceScanTests`
/// 的暫時允許清單（T27 搬）。
public enum L10nPanel: L10nCatalog, Sendable {
    case emptyRowsMessage
    /// T27：`PanelModel.notConnectedDetailText` 的通用兜底句（沒有 `mountTargetNote`
    /// 也沒有 `install.explanationDetail` 時）。
    case notConnectedGenericFallback
    /// T27：`PanelModel.connectCTAText`（`PanelModel+ConnectCTA.swift`）的兩個按鈕文案。
    case connectCTAConnect
    case connectCTAReplaceExternal
    /// T29：`NotConnectedView` 底部的求助按鈕——純資訊，沒有對應 `PanelAction`
    /// （見該檔 `.openHelp` 的既有接線）。
    case whatIsThisButton

    public func text(_ language: Language) -> String {
        switch self {
        case .emptyRowsMessage:
            switch language {
            case .english: return "Once Claude Code starts running, each session will show up here."
            case .traditionalChinese: return "Claude Code 開起來、開始跑之後，這裡會列出每個 session。"
            }
        case .notConnectedGenericFallback:
            switch language {
            case .english: return "Once connected, Claude Code's status will show up in the menu bar."
            case .traditionalChinese: return "接上之後，Claude Code 的執行狀態會顯示在選單列。"
            }
        case .connectCTAConnect:
            switch language {
            case .english: return "Connect"
            case .traditionalChinese: return "接上"
            }
        case .connectCTAReplaceExternal:
            switch language {
            case .english: return "Point at this app instead"
            case .traditionalChinese: return "改指向這個 App"
            }
        case .whatIsThisButton:
            switch language {
            case .english: return "What's this?"
            case .traditionalChinese: return "這是什麼？"
            }
        }
    }

    /// T27：B6 的「現有掛載指向哪裡」單一措辭（`PanelModel.mountTargetNote`）——帶參數，
    /// 語序在各語言分支自己決定，不共用位置樣板。
    public static func mountTargetNote(_ target: String, language: Language) -> String {
        switch language {
        case .english: return "Current mount points to: \(target)"
        case .traditionalChinese: return "現有掛載指向：\(target)"
        }
    }
}
