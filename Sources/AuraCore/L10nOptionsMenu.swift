/// T26 示範：Options 選單新增的「顯示語言」列——證明字串表機制從鍵到面板整條管路通。
/// `OptionsMenuModel` 其餘既有列的標題暫時仍是寫死的中文字面（T27 才搬），見
/// `L10nStrayLiteralSourceScanTests.pendingMigrationFiles` 的暫時允許清單。
public enum L10nOptionsMenu: L10nCatalog, Sendable {
    /// 純靜態、Options 列標題（D-1 示範 1/3）——標籤本身不隨「目前是哪個語言」改變寫法，
    /// 只有語系會變：英文顯示英文標籤、中文顯示中文標籤。
    case languageRowTitle

    public func text(_ language: Language) -> String {
        switch self {
        case .languageRowTitle:
            switch language {
            case .english: return "Language"
            case .traditionalChinese: return "顯示語言"
            }
        }
    }

    /// 帶參數字串（D-1 示範 2/3）——**不用 `String(format:)` 加位置參數**：每個顯示語言
    /// 分支直接用字串插值組出完整句子，語序由分支自己決定，不共用一個位置樣板（這正是
    /// D-1 點名要避免的形狀：中英文語序不同時，位置樣板會悄悄接錯詞而且測不出來）。
    /// `target` 一律用 `languageDisplayName` 給的自稱，不因目前顯示語言而換一種寫法
    /// （例如英文畫面下的目標若是中文，仍顯示「繁體中文」而不是英譯的 "Chinese"）。
    public static func languageRowSubtitle(switchingTo target: Language, displayLanguage: Language) -> String {
        let name = languageDisplayName(target)
        switch displayLanguage {
        case .english: return "Switch to \(name)"
        case .traditionalChinese: return "切換成\(name)"
        }
    }

    /// 語言名稱一律用該語言的自稱（endonym）——窮盡 `switch`、無 `default`：
    /// 新增語言忘了補這裡是編譯錯誤，不會漏字。
    public static func languageDisplayName(_ language: Language) -> String {
        switch language {
        case .english: return "English"
        case .traditionalChinese: return "繁體中文"
        }
    }
}
