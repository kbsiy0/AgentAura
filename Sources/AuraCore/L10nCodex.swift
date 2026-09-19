/// T07：Codex 在 Options `.mount` 群組的列標題——目前只放 T07 需要的三個鍵（`OptionsMenuModel.rows`
/// 的 `.connectCodex`／`.disconnectCodex` 兩個 action 各自的文案）。T09 會在這個檔案**追加**
/// 更多鍵（面板卡片的六態說明句、兩種 `CodexHookPathCheck.Rejection` 的文案、snippet 被扣住時
/// 的那句、七個 `CodexFailure` 的 banner 文案——見 spec §4.6／§4.9 的 T09 段），不是另開新檔。
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
        }
    }
}
