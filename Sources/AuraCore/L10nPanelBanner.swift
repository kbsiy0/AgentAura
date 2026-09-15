/// T27：`PanelBanner` 的固定文案 ＋ `PanelBanner.error(for: InstallerFailure)` 窮盡表
/// ＋ `InstallerFailure.mustMoveToApplicationsMessage`——三個檔案（`PanelModel.swift`／
/// `PanelBanner+InstallerFailure.swift`／`InstallerFailure.swift`）共用同一個「banner 文案」
/// 領域，收在一個檔案，同 `L10nInstallAffordance` 的切法（葉子字串住這裡，「哪個狀態用哪句」
/// 的邏輯留在各自的 production 檔）。
public enum L10nPanelBanner: L10nCatalog, Sendable {
    /// D-m：接上成功的固定文案——**不得**寫成「立即生效」，那是 S0-A1 修掉的謊
    /// （新掛載要下一個 Claude Code session 起才載入）。
    case connected
    /// S1-P4：措辭必須與「壞掉」明顯不同，否則使用者以為自己弄壞了。
    case disconnected
    case externalMountNeedsChoice
    case bundleIncomplete
    case writeTargetOccupied
    case verificationFailed
    case mustMoveToApplicationsMessage

    public func text(_ language: Language) -> String {
        switch self {
        case .connected:
            switch language {
            case .english:
                return "Connected · takes effect starting the next Claude Code session (windows already open aren't affected)"
            case .traditionalChinese:
                return "已接上 · 下一個 Claude Code session 起生效（現在開著的視窗不受影響）"
            }
        case .disconnected:
            switch language {
            case .english: return "Mount removed. Tap Connect to use it again."
            case .traditionalChinese: return "已移除掛載。要再用的話按［接上］。"
            }
        case .externalMountNeedsChoice:
            switch language {
            case .english: return "The current mount points somewhere else — choose whether to point it at this app instead."
            case .traditionalChinese: return "目前掛載指向別的地方，請選擇是否改指向這個 App。"
            }
        case .bundleIncomplete:
            switch language {
            case .english: return "The app's built-in plugin is incomplete. Please download and reinstall."
            case .traditionalChinese: return "App 內建的 plugin 不完整，請重新下載安裝。"
            }
        case .writeTargetOccupied:
            switch language {
            case .english: return "Couldn't connect: the target path is already in use."
            case .traditionalChinese: return "接上失敗：目標路徑被佔用。"
            }
        case .verificationFailed:
            switch language {
            case .english: return "Connected, but verification failed — please try again."
            case .traditionalChinese: return "接上後確認失敗，請再試一次。"
            }
        case .mustMoveToApplicationsMessage:
            switch language {
            case .english:
                return "Move AgentAura into the Applications folder (or out of Downloads) first, then continue."
            case .traditionalChinese:
                return "請先把 AgentAura 搬進「應用程式」資料夾（或搬出 Downloads）再繼續。"
            }
        }
    }

    /// §4.1：`connect()` 對有效掛載的冪等回應（S2-5）——不是錯誤，是「本來就好了」。
    public static func alreadyConnected(target: String?, language: Language) -> String {
        switch language {
        case .english:
            return "Already connected" + (target.map { " (pointing to \($0))" } ?? "")
        case .traditionalChinese:
            return "已經接上了" + (target.map { "（指向 \($0)）" } ?? "")
        }
    }

    /// A5（T11 commit3）：`replaceExternalMount` 成功的專屬文案——與一般 `connected()`
    /// 不對稱的地方正是這裡：這顆按鈕做的事是「把開發者的掛載換成 App 內建的凍結版」，
    /// 不明說換了什麼，使用者只會覺得「畫面變了但不知道為什麼」。
    public static func mountReplaced(from target: String?, language: Language) -> String {
        let suffix: String
        switch language {
        case .english: suffix = target.map { " (previous mount: \($0))" } ?? ""
        case .traditionalChinese: suffix = target.map { "（原掛載：\($0)）" } ?? ""
        }
        switch language {
        case .english:
            return "Connected · mount switched to this app\(suffix) · takes effect starting the next Claude Code session"
        case .traditionalChinese:
            return "已接上 · 掛載已換成這個 App\(suffix) · 下一個 Claude Code session 起生效"
        }
    }

    public static func renameFailed(code: Int32, language: Language) -> String {
        switch language {
        case .english: return "Couldn't connect (error code \(code))."
        case .traditionalChinese: return "接上失敗（錯誤碼 \(code)）。"
        }
    }
}
