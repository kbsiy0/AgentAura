/// T27：`OptionsMenuModel.rows(...)` 其餘列的標題／副標——`L10nOptionsMenu.swift` 只留
/// T26 示範用的「顯示語言」列，其餘搬進這個獨立檔案（同 design doc §2 的切法：單一 domain
/// 太肥時拆成更小的 domain，這裡沿用同一個 `OptionsRow` 領域，只是換檔案）。
public enum L10nOptionsMenuRows: L10nCatalog, Sendable {
    case help
    case launchAtLogin
    case reduceMotion
    /// 減少動態：系統已強制開啟時的說明（按了也沒用，系統值贏）。
    case reduceMotionForcedBySystem
    /// 減少動態：使用者自己打開時的說明（T13 S1-4'：等你／錯誤只靠顏色區分）。
    case reduceMotionUserEnabledWarning
    case iconPlate
    /// T32：Options 列標題——「選單列 icon 造型」（點擊彈出造型選單）。
    case iconShape
    case resetColors
    case reconnect
    case recheckHook
    case disconnect
    case uninstall
    case about
    case reportIssue
    case quit
    /// T29：`OptionsRowContent`（`OptionsSectionView.swift`）的開關狀態字樣——A9（T11 commit3）
    /// 的既有理由：離屏渲染下 `Toggle` on／off 兩張圖沒有視覺差異，狀態另外自己畫一個
    /// 字樣＋顏色。
    case toggleOn
    case toggleOff

    public func text(_ language: Language) -> String {
        switch self {
        case .help:
            switch language {
            case .english: return "Help & quick start…"
            case .traditionalChinese: return "說明與快速上手…"
            }
        case .launchAtLogin:
            switch language {
            case .english: return "Launch at login"
            case .traditionalChinese: return "開機自動啟動"
            }
        case .reduceMotion:
            switch language {
            case .english: return "Reduce motion"
            case .traditionalChinese: return "減少動態"
            }
        case .reduceMotionForcedBySystem:
            switch language {
            case .english: return "Already on in System Settings"
            case .traditionalChinese: return "已在系統設定開啟"
            }
        case .reduceMotionUserEnabledWarning:
            switch language {
            case .english: return "With animation off, \"waiting\" and \"error\" are only told apart by color"
            case .traditionalChinese: return "動畫關閉後，「等你」與「錯誤」只靠顏色區分"
            }
        case .iconPlate:
            switch language {
            case .english: return "Icon backdrop"
            case .traditionalChinese: return "燈條底板"
            }
        case .iconShape:
            switch language {
            case .english: return "Menu bar icon shape"
            case .traditionalChinese: return "選單列 icon 造型"
            }
        case .resetColors:
            switch language {
            case .english: return "Reset colors"
            case .traditionalChinese: return "重設顏色"
            }
        case .reconnect:
            switch language {
            case .english: return "Reconnect Claude Code"
            case .traditionalChinese: return "重新接上 Claude Code"
            }
        case .recheckHook:
            switch language {
            case .english: return "Check again"
            case .traditionalChinese: return "再檢查一次"
            }
        case .disconnect:
            switch language {
            case .english: return "Remove mount…"
            case .traditionalChinese: return "移除掛載…"
            }
        case .uninstall:
            switch language {
            case .english: return "Completely remove AgentAura…"
            case .traditionalChinese: return "完整移除 AgentAura…"
            }
        case .about:
            switch language {
            case .english: return "About AgentAura"
            case .traditionalChinese: return "關於 AgentAura"
            }
        case .reportIssue:
            switch language {
            case .english: return "Report an issue…"
            case .traditionalChinese: return "回報問題…"
            }
        case .quit:
            switch language {
            case .english: return "Quit AgentAura ⌘Q"
            case .traditionalChinese: return "離開 AgentAura ⌘Q"
            }
        case .toggleOn:
            switch language {
            case .english: return "On"
            case .traditionalChinese: return "開"
            }
        case .toggleOff:
            switch language {
            case .english: return "Off"
            case .traditionalChinese: return "關"
            }
        }
    }

    /// T19：底板關＋目前 palette 有任一可改色狀態在淺色選單列上「幾乎看不見」時的提醒——
    /// 帶參數（受影響的 activity 名單），語序在各語言分支自己決定。
    public static func lightBarWarning(names: [String], language: Language) -> String {
        let joined: String
        switch language {
        case .english: joined = names.map { "\"\($0)\"" }.joined(separator: ", ")
        case .traditionalChinese: joined = names.map { "「\($0)」" }.joined(separator: "、")
        }
        switch language {
        case .english:
            return "With the backdrop off, these colors are hard to see on a light menu bar: \(joined)"
        case .traditionalChinese:
            return "底板關閉時，\(joined)的顏色在淺色選單列上幾乎看不見"
        }
    }
}
