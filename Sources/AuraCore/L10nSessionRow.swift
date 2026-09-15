/// T27：`PanelViewModel` 面板列文案搬進字串表——headline／detail／relativeTime／`PanelRow.footer`
/// 用到的所有字面，一個領域一個檔案（同 `L10nPanel`／`L10nOptionsMenu` 的切法）。
public enum L10nSessionRow: L10nCatalog, Sendable {
    /// headline：waiting 的固定前綴，後面接工具名／通知內容（`waitingApprovalOf`）。
    case waitingApprovalPrefix
    /// headline：waiting 且沒有任何 tool／通知內容時的兜底詞。
    case toolFallback
    /// headline：error 的兜底詞（`toolError`／`errorType` 都沒有時）。
    case executionFailedFallback
    /// headline：done 的兜底詞（`summarise(lastMessage)` 是 nil 時）。
    case doneFallback
    /// headline：working 且主 agent 已完成、只剩背景 subagent 還在跑。
    case mainAgentDoneBackgroundRunning
    /// headline：working 的兜底詞（沒有 `currentTool`／`subagentTool` 時）。
    case executingFallback
    /// headline：idle。
    case idleHeadline
    /// detail：主 agent 完成訊息的前綴（working 且 mainActivity 已完成時）。
    case mainAgentPrefix
    /// detail：本輪耗時的前綴。
    case thisTurnPrefix
    /// relativeTime：< 5 秒視為「剛剛」。
    case justNow
    /// relativeTime：非「剛剛」時的「⟨時長⟩前」後綴。
    case agoSuffix
    /// `PanelRow.footer`：已結束列的存活訊號，刻意放在行首（S1-B）。
    case endedMarker

    public func text(_ language: Language) -> String {
        switch self {
        case .waitingApprovalPrefix:
            switch language {
            case .english: return "Needs your OK: "
            case .traditionalChinese: return "等你批准："
            }
        case .toolFallback:
            switch language {
            case .english: return "input"
            case .traditionalChinese: return "輸入"
            }
        case .executionFailedFallback:
            switch language {
            case .english: return "Failed"
            case .traditionalChinese: return "執行失敗"
            }
        case .doneFallback:
            switch language {
            case .english: return "Done"
            case .traditionalChinese: return "已完成"
            }
        case .mainAgentDoneBackgroundRunning:
            switch language {
            case .english: return "Main agent done, background work still running"
            case .traditionalChinese: return "主 agent 已完成，背景 subagent 還在跑"
            }
        case .executingFallback:
            switch language {
            case .english: return "Running"
            case .traditionalChinese: return "執行中"
            }
        case .idleHeadline:
            switch language {
            case .english: return "Waiting for your next message"
            case .traditionalChinese: return "等你下指令"
            }
        case .mainAgentPrefix:
            switch language {
            case .english: return "Main agent: "
            case .traditionalChinese: return "主 agent："
            }
        case .thisTurnPrefix:
            switch language {
            case .english: return "This turn "
            case .traditionalChinese: return "本輪 "
            }
        case .justNow:
            switch language {
            case .english: return "just now"
            case .traditionalChinese: return "剛剛"
            }
        case .agoSuffix:
            switch language {
            case .english: return " ago"
            case .traditionalChinese: return "前"
            }
        case .endedMarker:
            switch language {
            case .english: return "Ended"
            case .traditionalChinese: return "已結束"
            }
        }
    }

    /// 帶參數（子任務／工具失敗次數）——英文單複數要分（1 個不加 s），
    /// 不共用中文那種「恆用『個』」的位置樣板。
    public static func subtaskCount(_ n: Int, language: Language) -> String {
        switch language {
        case .english: return "\(n) subtask\(n == 1 ? "" : "s")"
        case .traditionalChinese: return "\(n) 個子任務"
        }
    }

    public static func toolFailureCount(_ n: Int, language: Language) -> String {
        switch language {
        case .english: return "\(n) tool failure\(n == 1 ? "" : "s")"
        case .traditionalChinese: return "\(n) 次工具失敗"
        }
    }
}
