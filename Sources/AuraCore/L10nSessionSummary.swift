/// T27：`SessionSummary.text` 搬進字串表。D-1 規定「不用 `String(format:)` 共用位置樣板」——
/// `attentionSummary`／`liveCount`／`doneCount` 各自對 `Language` 窮盡 `switch`，每個分支
/// 組出完整句子；中英文剛好都是「數字＋名詞片語」語序是巧合，不是共用同一個模板算出來的。
public enum L10nSessionSummary: L10nCatalog, Sendable {
    case noActiveSessions

    public func text(_ language: Language) -> String {
        switch self {
        case .noActiveSessions:
            switch language {
            case .english: return "No active sessions"
            case .traditionalChinese: return "沒有活著的 session"
            }
        }
    }

    /// 兩個呼叫端各自的用詞（`PanelViewModel.title` 用「在等你」／`TooltipText.sessionSummary`
    /// 用「需要你」，理由見 `SessionSummary.swift` 的既有 doc comment）收成型別，不再傳裸字串。
    public enum AttentionWord: Sendable, Equatable {
        case waitingForYou
        case needsYou

        func text(_ language: Language) -> String {
            switch self {
            case .waitingForYou:
                switch language {
                case .english: return "waiting for you"
                case .traditionalChinese: return "在等你"
                }
            case .needsYou:
                switch language {
                case .english: return "needs you"
                case .traditionalChinese: return "需要你"
                }
            }
        }
    }

    public static func attentionSummary(count: Int, running: Int, word: AttentionWord, language: Language) -> String {
        let w = word.text(language)
        switch language {
        case .english:
            return running > 0 ? "\(count) \(w) · \(running) running" : "\(count) \(w)"
        case .traditionalChinese:
            return running > 0 ? "\(count) 個\(w) · \(running) 個在跑" : "\(count) 個\(w)"
        }
    }

    public static func liveCount(_ live: Int, language: Language) -> String {
        switch language {
        case .english: return "\(live) session\(live == 1 ? "" : "s") running"
        case .traditionalChinese: return "\(live) 個 session 在跑"
        }
    }

    public static func doneCount(_ done: Int, language: Language) -> String {
        switch language {
        case .english: return "\(done) done"
        case .traditionalChinese: return "\(done) 個已完成"
        }
    }
}
