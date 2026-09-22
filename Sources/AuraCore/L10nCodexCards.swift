/// T13（persona r1 修復批次）：Codex 卡片新增文案獨立成自己的 `L10nCatalog`——**不塞進**
/// `L10nCodex.swift`（158/200，三個新 case 連 doc 會撞上限，且 `text(_:)` 的窮盡 `switch`
/// 無法跨檔拆，同 `L10nUninstallConfirmation` 從 `L10nConfirmationAlerts` 分出去的既有理由）、
/// **也不塞進** `L10nPanel.swift`（55/200，行數塞得下，但那個檔的既有語意是「面板本體的
/// 通用字串」——空列訊息、CTA 按鈕、求助按鈕，把 Codex 卡片的四句混進去會讓「哪個 catalog
/// 管什麼」這條線消失，本 change 已經為了同一個理由把 `L10nCodex+Failures` 拆出去過）。
///
/// 四個 case 一次建檔（雖然只有 `unsupportedCharacterWayOut` 在 T13d 這個 commit 被消費）：
/// `mergeInstruction`／`helpLinkLabel` 給 T13h、`staleOtherCopyIntro` 給 T13e——三個子項
/// 序列共用同一個新檔（`CodexSectionView.swift`／`L10nCodexCards.swift` 是鏈 B 內序列，
/// 見 plan §T13 衝突檔表），一次把窮盡 `switch` 的骨架搭好，後面兩個子項只加消費端、
/// 不再改這裡的 case 集合。
public enum L10nCodexCards: L10nCatalog, Sendable {
    /// D-w（T13d）：`.unsupportedCharacter` 卡片的出路句——接在指名字元的解釋句
    /// （`L10nCodex.unsupportedCharacterExplanation`）之後，取代被扣住的 snippet
    /// （R-10／r13：有 rejection 就扣住，見 `CodexHooksJSON.withheldSnippet`）。
    case unsupportedCharacterWayOut
    /// D-aa（T13h）：`.occupiedByOther` 有 snippet 時的合併指示——卡片前一句才說
    /// 「我們不會動你的檔」，這句補上「你自己要做什麼」，擋的是「手滑貼上就整份取代自己
    /// hooks.json」那個唯一危險點。
    case mergeInstruction
    /// D-aa（T13h）：通往 help 的按鈕字樣——按下去送出既有的 `.openHelp` action，
    /// 不開第四個 `PanelAction`（合併細節一行寫不完，help 兩份文件已經有那段）。
    case helpLinkLabel
    /// D-x（T13e）：`staleOtherCopyMessage` 拆開後的中性開場句——只講可觀測的事實
    /// （這份設定指向另一個位置的 AgentAura），刪掉「下次開機就會消失」子句
    /// （那句對 `.unsupportedCharacter` 可查證為假）。第二段重用 `.blockedByBundlePath`
    /// 那組既有文案（`.mustMoveToApplications` 用既有兩句、`.unsupportedCharacter` 用
    /// `unsupportedCharacterExplanation` ＋ `unsupportedCharacterWayOut`），零新增文案。
    case staleOtherCopyIntro

    public func text(_ language: Language) -> String {
        switch self {
        case .unsupportedCharacterWayOut:
            switch language {
            case .english:
                return "Move the app somewhere without that character — Applications, for example — then come back and connect."
            case .traditionalChinese:
                return "把 App 移到路徑不含該字元的位置（例如『應用程式』），再回來重新接上。"
            }
        case .mergeInstruction:
            switch language {
            case .english:
                return "Add these entries into your existing hooks object — don't replace the whole file."
            case .traditionalChinese:
                return "把這些 entry 併進你現有的 hooks 物件，不要整份取代。"
            }
        case .helpLinkLabel:
            switch language {
            case .english: return "Show me how"
            case .traditionalChinese: return "教我怎麼做"
            }
        case .staleOtherCopyIntro:
            switch language {
            case .english: return "This setup points at a different copy of AgentAura."
            case .traditionalChinese: return "這份設定指向另一個位置的 AgentAura。"
            }
        }
    }
}
