/// T29：D-1「完整移除」確認框（`UninstallConfirmation`，`AppEnvironment.swift`）的文案，
/// 以及 `UninstallFailureLog` 唯一的診斷紀錄行（`Uninstaller.swift`）——後者嚴格說不是
/// 面板 UI，但一樣是使用者可能會打開來看的文字（`docs/INSTALL.md` 疑難排解一節請人自己看
/// 這個檔案），D-1 涵蓋的是「生產碼中文字串字面」，不是只有 UI，沒有理由排除在外。
///
/// 中文文案是使用者親自要求改寫過的版本（team-lead 原話：「太文謅謅了，稍微排版一下吧，
/// 條列式一點，使用者大部分都不是工程師，不用寫太技術」）——英文版維持同樣的水準：
/// 條列、短句、講使用者感受得到的後果，不出現 mount／symlink／persistent domain／registry
/// 這類字眼。`UninstallConfirmationCopyTests` 中英文各自守一半語意標記，不是逐字相等。
public enum L10nUninstallConfirmation: L10nCatalog, Sendable {
    case title
    case body
    case confirmButtonTitle

    public func text(_ language: Language) -> String {
        switch self {
        case .title:
            switch language {
            case .english: return "Completely remove AgentAura?"
            case .traditionalChinese: return "完整移除 AgentAura？"
            }
        case .body:
            switch language {
            // 英文條列**一律祈使句**：標題是 "Here's what this will do, in order:"，
            // 每一條都要能直接接在它後面讀得通。中文原文混用「關閉…」與「選單列不再…」
            // 在中文讀起來自然，直譯成英文會變成祈使句與陳述句混雜，像沒校對過。
            // 這是「照著中文的形狀翻」與「讓英文自己讀得順」之間選了後者。
            case .english:
                return """
                    Here's what this will do, in order:

                    • Turn off launch at login
                    • Stop showing menu bar status
                    • Reset colors and toggles to default
                    • Clear all usage history
                    • Move the app to Trash

                    Usually recoverable until you empty the Trash.
                    """
            case .traditionalChinese:
                return """
                    這會依序做這些事：

                    • 關閉開機自動啟動
                    • 選單列不再顯示狀態
                    • 顏色和開關恢復預設
                    • 清空所有使用紀錄
                    • 移到垃圾桶

                    垃圾桶清空前，通常都能救回來。
                    """
            }
        case .confirmButtonTitle:
            switch language {
            case .english: return "Completely remove"
            case .traditionalChinese: return "完整移除"
            }
        }
    }

    /// `UninstallFailureLog.record` 失敗時唯一寫的一行——見該型別 doc comment：
    /// 覆蓋而非累加，只在乎「上一次」有沒有失敗。
    public static func failureLogLine(timestamp: String, source: String, error: String, language: Language) -> String {
        switch language {
        case .english: return "[\(timestamp)] Trash operation failed: source \(source), error: \(error)\n"
        case .traditionalChinese: return "[\(timestamp)] 垃圾桶動作失敗：來源 \(source)，錯誤：\(error)\n"
        }
    }
}
