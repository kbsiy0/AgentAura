/// T07：`OptionsMenuModel.rows(...)` 的 Codex 那半，搬進獨立檔案讓 `OptionsMenuModel.swift`
/// 留在 `Sources/` 200 行上限內（同 `CodexState.swift`／`CodexState+From.swift` 的既有切法：
/// 資料型別與判定分檔）。
extension OptionsMenuModel {
    /// T07（CX20，spec §4.6 表，R-9）：Codex 在 `.mount` 群組的列——`.unavailable`／
    /// `.occupiedByOther`／`.blockedByBundlePath` 零列（那三態的說明住在面板卡片，不進
    /// Options 選單，D-j／R-10）；`.notConnected`／`.connected` 各恰一列；`.connectedStalePath`
    /// 依 `pathRejection` 分兩列（`nil`：多給一顆「重新接上」）或一列（非 nil：**不給**
    /// 「重新接上」按鈕——R-9 的重點是那顆按鈕在路徑被拒時必須不存在，不是存在但 disabled，
    /// 否則使用者按下去會先 `disconnect` 掉一份還在運作的檔，見 CX39）。窮盡 `switch`
    /// 對 `CodexStateKind`，不得有 `default`——理由同 `CodexState.kind`。
    ///
    /// 不是 `private`：這個函式住的檔案跟呼叫它的 `rows(...)`（`OptionsMenuModel.swift`）
    /// 不同檔，`private` 在另一個檔案裡看不到；維持 module-internal（不加 `public`），
    /// 不對外暴露就好。
    static func codexRows(_ codex: CodexState, pathRejection: CodexHookPathCheck.Rejection?,
                          language: Language) -> [OptionsRow] {
        switch codex.kind {
        case .unavailable, .occupiedByOther, .blockedByBundlePath:
            return []
        case .notConnected:
            return [OptionsRow(title: L10nCodex.connectRow.text(language), action: .connectCodex,
                               isDisabled: false, toggleValue: nil, group: .mount)]
        case .connected:
            return [OptionsRow(title: L10nCodex.disconnectMountRow.text(language), action: .disconnectCodex,
                               isDisabled: false, toggleValue: nil, group: .mount)]
        case .connectedStalePath:
            let disconnectRow = OptionsRow(title: L10nCodex.disconnectMountRow.text(language),
                                           action: .disconnectCodex, isDisabled: false,
                                           toggleValue: nil, group: .mount)
            guard pathRejection == nil else { return [disconnectRow] }
            let reconnectRow = OptionsRow(title: L10nCodex.reconnectRow.text(language),
                                          action: .connectCodex, isDisabled: false,
                                          toggleValue: nil, group: .mount)
            return [reconnectRow, disconnectRow]
        }
    }
}
