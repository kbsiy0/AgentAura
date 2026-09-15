/// T27：`InstallAffordance.swift`（`InstallState.healthLabel`／`explanationDetail`／
/// `hookBlockedPrescription`／`hookUnconfirmedPrescription`）搬進字串表——這是 `AuraCore`
/// 裡字面最多的檔案（design doc §1：21 個），窮盡 `InstallState` 的每一種狀態。
///
/// 這裡只放**葉子字串**；「哪個狀態該用哪個 key、`connected` 的三個子句怎麼拼成一句」
/// 那些邏輯留在 `InstallAffordance.swift`（同 `L10nPanel.emptyRowsMessage` 的切法：
/// L10n 檔只管「這個 key 兩種語言各是什麼」，production 檔管「什麼時候用哪個 key」）。
public enum L10nInstallAffordance: L10nCatalog, Sendable {
    // MARK: - healthLabel

    case claudeNotFoundLabel
    case notConnectedLabel
    case connectedBase
    case connectedExternalOwnerClause
    case connectedCheckingClause
    case connectedUnverifiedClause
    case brokenTargetMissing
    case brokenTargetUnresolvable
    case brokenNotAPlugin
    case brokenHookMissing
    case brokenHookNotExecutable
    case brokenHookBlockedOrBrokenLabel
    case brokenHookUnconfirmedLabel
    case brokenOccupiedByDirectory
    case brokenOccupiedByFile

    // MARK: - explanationDetail（非 healthLabel 專用的另外 4 句）

    case claudeNotFoundExplanation
    case occupiedByFileExplanation
    case occupiedByDirectoryExplanation
    case genericConnectExplanation

    // MARK: - 與按鈕失敗 banner 共用的兩句處方（S1-1：同一句常數，不重複維護）

    case hookBlockedPrescription
    case hookUnconfirmedPrescription

    public func text(_ language: Language) -> String {
        switch self {
        case .claudeNotFoundLabel:
            switch language {
            case .english: return "Claude Code not found"
            case .traditionalChinese: return "找不到 Claude Code"
            }
        case .notConnectedLabel:
            switch language {
            case .english: return "Not connected yet"
            case .traditionalChinese: return "還沒接上"
            }
        case .connectedBase:
            switch language {
            case .english: return "Connected"
            case .traditionalChinese: return "已接上"
            }
        case .connectedExternalOwnerClause:
            switch language {
            case .english: return "your repo's mount"
            case .traditionalChinese: return "你的 repo 掛載"
            }
        case .connectedCheckingClause:
            switch language {
            case .english: return "checking…"
            case .traditionalChinese: return "檢查中…"
            }
        case .connectedUnverifiedClause:
            switch language {
            case .english: return "unverified"
            case .traditionalChinese: return "未驗證"
            }
        case .brokenTargetMissing:
            switch language {
            case .english: return "Can't connect: the app was moved"
            case .traditionalChinese: return "接不上：App 被搬走了"
            }
        case .brokenTargetUnresolvable:
            switch language {
            case .english: return "Can't connect: the mount can't be resolved"
            case .traditionalChinese: return "接不上：掛載解不開"
            }
        case .brokenNotAPlugin:
            switch language {
            case .english: return "Can't connect: the mount contents are wrong"
            case .traditionalChinese: return "接不上：掛載內容不對"
            }
        case .brokenHookMissing:
            switch language {
            case .english: return "Can't connect: the hook program is missing"
            case .traditionalChinese: return "接不上：少了 hook 程式"
            }
        case .brokenHookNotExecutable:
            switch language {
            case .english: return "Can't connect: the hook isn't executable"
            case .traditionalChinese: return "接不上：hook 沒有執行權限"
            }
        case .brokenHookBlockedOrBrokenLabel:
            switch language {
            case .english: return "Can't connect: macOS blocked the hook"
            case .traditionalChinese: return "接不上：macOS 擋住了 hook"
            }
        case .brokenHookUnconfirmedLabel:
            switch language {
            case .english: return "Can't connect: couldn't confirm the hook works"
            case .traditionalChinese: return "接不上：無法確認 hook 能不能跑"
            }
        case .brokenOccupiedByDirectory:
            switch language {
            case .english: return "Taken by another install"
            case .traditionalChinese: return "已被其他安裝佔用"
            }
        case .brokenOccupiedByFile:
            switch language {
            case .english: return "The path is taken by a file"
            case .traditionalChinese: return "路徑被一個檔案佔住"
            }
        case .claudeNotFoundExplanation:
            switch language {
            case .english:
                return "Looks like Claude Code hasn't run yet. Run it once (ask it anything), then come back — connecting should just work."
            case .traditionalChinese:
                return "看起來還沒用過 Claude Code，先跑一次（隨便問它一句話）再回來，通常就能一鍵接上。"
            }
        case .occupiedByFileExplanation:
            switch language {
            case .english:
                return "~/.claude/skills/agentaura is currently a plain file, not a mount point. Delete or move it, then choose \"Reconnect Claude Code\" from Options."
            case .traditionalChinese:
                return "~/.claude/skills/agentaura 目前是一個普通檔案，不是掛載用的位置。手動刪除或搬走這個檔案，再從 Options 選「重新接上 Claude Code」。"
            }
        case .occupiedByDirectoryExplanation:
            switch language {
            case .english:
                return "~/.claude/skills/agentaura is currently in use by another install — AgentAura won't touch it. Once you're sure that install is no longer needed, remove the directory yourself, then choose \"Reconnect Claude Code\" from Options."
            case .traditionalChinese:
                return "~/.claude/skills/agentaura 目前是別的安裝在用的目錄，AgentAura 不會動它。確認那個安裝不再需要之後手動移除該目錄，再從 Options 選「重新接上 Claude Code」。"
            }
        case .genericConnectExplanation:
            switch language {
            case .english: return "The button below will rebuild the mount — that usually fixes it."
            case .traditionalChinese: return "按下面的按鈕會重新建立掛載，通常就能修好。"
            }
        case .hookBlockedPrescription:
            switch language {
            case .english:
                return "macOS blocked the hook. Drag the app into Applications and reopen it, or allow it in System Settings → Privacy & Security."
            case .traditionalChinese:
                return "macOS 擋住了 hook。把 App 拖進「應用程式」再開一次；或到系統設定 → 隱私與安全性允許。"
            }
        case .hookUnconfirmedPrescription:
            switch language {
            case .english: return "Couldn't confirm the hook works yet — try again in a moment."
            case .traditionalChinese: return "無法確認 hook 能不能跑，稍後再試一次。"
            }
        }
    }
}
