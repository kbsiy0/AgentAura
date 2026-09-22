/// T07：Codex 在 Options `.mount` 群組的列標題（`connectRow`／`reconnectRow`／
/// `disconnectMountRow`）。T09 追加：面板卡片的六態說明句、兩種 `CodexHookPathCheck.Rejection`
/// 的文案、snippet 被扣住時的那句（R-10）、接上成功 banner（D-m）、三個 `CodexFailure` 的
/// 固定 banner 文案——都是**不帶參數**的葉子字串。**帶參數**的（字元插值、錯誤碼插值、
/// 七個 `CodexFailure` 的窮盡 dispatcher）住 `L10nCodex+Failures.swift`——Swift enum 的
/// case 不能用 extension 補，但 `text(_:)` 以外的 static func 可以，藉此把本檔留在
/// `Sources/` 200 行上限內（同 `CodexState.swift`／`CodexState+From.swift` 的既有切法）。
public enum L10nCodex: L10nCatalog, Sendable {
    /// `.notConnected` 那一列：還沒接過，語氣是「第一次接上」。
    case connectRow
    /// `.connectedStalePath`（`pathRejection == nil`）那一列：曾經接過、現在指向的路徑失效
    /// （app 搬家），語氣是「重新」——跟 `connectRow` 用同一個 `.connectCodex` action（D-k：
    /// 不開第四個 case），只是文案依當下狀態換一句話，同 Claude 側 `.connect` 的既有形狀相反：
    /// Claude 側「重新接上 Claude Code」無論狀態都用同一句，這裡刻意分兩句是 spec §4.6 表
    /// 逐字寫明的用詞（「接上 Codex」vs「重新接上 Codex」），照 spec，不是自行加碼。
    case reconnectRow
    /// `.connected`／`.connectedStalePath` 都會出現的那一列：拆掉 Codex 這邊的掛載。
    case disconnectMountRow
    /// `.notConnected` 面板卡片的單行提示（R-3：不依 Claude 安裝狀態降級，一律如此）。
    case notConnectedPrompt
    /// `.connectedStalePath`，`pathRejection == nil`：app 搬家，一鍵可重接。§4.6 表逐字寫明。
    case staleMovedPrompt
    /// `.occupiedByOther`：兩種 snippet 有無都共用的開場句。
    case occupiedIntro
    /// `.occupiedByOther`，`codexSnippet == nil`：R-10——路徑會在下次開機消失，
    /// 寧可不給也不給一份會過期的設定。§4.6 表逐字寫明。
    case occupiedSnippetWithheldReason
    /// `.blockedByBundlePath(.mustMoveToApplications)` 卡片的「解釋」半句——「出路」半句
    /// 重用既有的 `InstallerFailure.mustMoveToApplicationsMessage`（同一個實體理由，
    /// 不維護第二份「把 App 移到應用程式」的措辭）。
    case blockedPathExplanation
    /// 面板卡片內「複製」snippet 的按鈕字樣（`.occupiedByOther`／
    /// `.blockedByBundlePath(.unsupportedCharacter)` 兩態共用）。
    case copyButtonLabel
    /// D-m：接上 Codex 成功的固定 banner——**必須同時**講「下一個 Codex session 起生效」
    /// 與「Codex 會問你一次是否信任」（F5，P4 硬下限：不懂信任提示的 vibe coding 使用者，
    /// 按下去之前與之後都要看到這句）。與 Claude 側 `.connected` 不是同一句
    /// （Claude 側沒有「信任提示」這件事）。
    case connectedBanner
    /// T10：拆掉 Codex 掛載成功的固定文案——同 Claude 側 `.disconnected(language:)` 的既有
    /// 理由（`.text` 一律不給預設值），但不重用那句：Claude 側寫「要再用的話按［接上］」，
    /// 這裡的按鈕字樣是「接上 Codex」／「重新接上 Codex」（`L10nCodex.connectRow`／
    /// `reconnectRow`），照抄 Claude 側措辭會提到一顆不存在的按鈕。
    case disconnectedBanner
    /// `CodexFailure.codexHomeMissing` 的 banner。
    case codexHomeMissingBanner
    /// `CodexFailure.alreadyExists` 的 banner。
    case alreadyExistsBanner
    /// `CodexFailure.notOurs` 的 banner。
    case notOursBanner

    public func text(_ language: Language) -> String {
        switch self {
        case .connectRow:
            switch language {
            case .english: return "Connect Codex"
            case .traditionalChinese: return "接上 Codex"
            }
        case .reconnectRow:
            switch language {
            case .english: return "Reconnect Codex"
            case .traditionalChinese: return "重新接上 Codex"
            }
        case .disconnectMountRow:
            switch language {
            case .english: return "Remove Codex mount…"
            case .traditionalChinese: return "移除 Codex 掛載…"
            }
        case .notConnectedPrompt:
            switch language {
            case .english:
                return "Codex's hook isn't connected yet — connect it to see Codex sessions in this panel too."
            case .traditionalChinese:
                return "還沒接上 Codex 的 hook——接上後，Codex 的 session 也會顯示在這個面板裡。"
            }
        case .staleMovedPrompt:
            switch language {
            case .english: return "AgentAura moved — reconnect to keep this working."
            case .traditionalChinese: return "App 移動過，要重新接上"
            }
        case .occupiedIntro:
            switch language {
            case .english: return "You already have your own ~/.codex/hooks.json — we won't touch it."
            case .traditionalChinese: return "你已經有自己的 ~/.codex/hooks.json，我們不會動它。"
            }
        case .occupiedSnippetWithheldReason:
            switch language {
            case .english:
                return "Move the app into Applications first — only then can we hand you a setup that won't expire."
            case .traditionalChinese:
                return "先把 App 移到『應用程式』，我們才給得出一份不會過期的設定"
            }
        case .blockedPathExplanation:
            switch language {
            case .english:
                return "AgentAura is running from a location that will disappear after the next restart, so it can't write Codex's setup here."
            case .traditionalChinese:
                return "AgentAura 現在跑在一個下次重開機就會消失的位置，沒辦法把 Codex 的設定寫在這裡。"
            }
        case .copyButtonLabel:
            switch language {
            case .english: return "Copy"
            case .traditionalChinese: return "複製"
            }
        case .connectedBanner:
            switch language {
            case .english:
                return """
                    Connected to Codex · takes effect starting the next Codex session; Codex will ask you \
                    once whether to trust this hook — you need to approve it for the hook to take effect.
                    """
            case .traditionalChinese:
                return "已接上 Codex · 下一個 Codex session 起生效；Codex 啟動時會問你一次是否信任這個 hook，要按同意才會生效。"
            }
        case .disconnectedBanner:
            switch language {
            case .english: return "Removed Codex's hook mount."
            case .traditionalChinese: return "已移除 Codex 掛載。"
            }
        case .codexHomeMissingBanner:
            switch language {
            case .english: return "Couldn't find the ~/.codex folder, so Codex can't be connected."
            case .traditionalChinese: return "找不到 ~/.codex 資料夾，沒辦法接上 Codex。"
            }
        case .alreadyExistsBanner:
            switch language {
            case .english: return "Codex's hooks.json already has content — we won't overwrite it."
            case .traditionalChinese: return "Codex 的 hooks.json 已經有內容，我們不會覆蓋它。"
            }
        case .notOursBanner:
            switch language {
            case .english: return "This hooks.json wasn't written by us, so we're leaving it alone."
            case .traditionalChinese: return "這份 hooks.json 不是我們寫的，不會動它。"
            }
        }
    }

    /// CX24④ 用的兩個關鍵詞（`CodexWiringSmokeTests`：composition-root smoke 用預設語言
    /// `.english` 建 `AppDelegate`，不吃 `language`）——**必須是** `connectedBanner.text(.english)`
    /// **的逐字子字串**，兩者漂移時這裡要跟著改（`L10nCodexConnectedBannerTests` 守）。
    public static let nextSessionTakesEffectKeyword = "next Codex session"
    public static let codexWillAskToTrustKeyword = "trust"
}
