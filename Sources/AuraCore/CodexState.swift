/// spec §3／§4.6（r8）：Codex 掛載在面板／Options 上的六態。判定住在
/// `CodexState.from(_:recordedContents:currentExpectedContents:pathRejection:)`（`CodexState+From.swift`）——
/// 這裡只是資料。
public enum CodexState: Equatable, Sendable {
    /// `~/.codex` 不存在或不是目錄（D-j）：面板與 Options 完全沒有任何 Codex 元素。
    case unavailable
    /// `~/.codex` 是目錄、`hooks.json` 不存在，且目前這個行程的 bundle 路徑沒有被
    /// `CodexHookPathCheck` 拒絕。
    case notConnected
    /// 磁碟上的 `hooks.json` 內容、我們記錄的憑證、以及「這個行程現在預期產生的內容」
    /// 三者逐位元組相等。
    case connected
    /// 磁碟 == 憑證，但 != 現在這個行程預期產生的內容——app 搬家，或從另一份副本啟動（R-6）。
    /// **不帶** `pathRejection`：判定表（見 `CodexState+From.swift`）裡 `pathRejection` 對這一列
    /// 是「任意」，UI 要不要給「重新接上」是 `OptionsMenuModel.rows` 另外吃
    /// `codexPathRejection` 參數才能回答的問題（§4.6，R-9），不是這個 case 自己的欄位。
    case connectedStalePath
    /// 路徑上有別人的東西：型別不是 regular file，或內容跟我們的憑證不符（別人的合法 JSON、
    /// 或憑證遺失後我們自己的舊檔看起來也像「別人的」）。
    case occupiedByOther
    /// `~/.codex` 是目錄、`hooks.json` 不存在，但目前這個行程的 bundle 路徑被
    /// `CodexHookPathCheck` 拒絕——explain-only，不給「接上 Codex」（R-5／R-9）。
    case blockedByBundlePath(CodexHookPathCheck.Rejection)

    /// 窮盡 switch，**不得有 `default`**——那正是 `CodexStateKind` 這個平行型別存在的
    /// 唯一理由：新增一個 case 時，這裡與 `samples(_:)` 會編不過，逼你同時補齊；加一個
    /// `default` 看起來像防禦性寫法，實際是讓整條定義域推導鏈靜默失效（D-r，同
    /// `CodexHookPathCheck.Rejection.kind` 逐字一樣的理由）。
    public var kind: CodexStateKind {
        switch self {
        case .unavailable: .unavailable
        case .notConnected: .notConnected
        case .connected: .connected
        case .connectedStalePath: .connectedStalePath
        case .occupiedByOther: .occupiedByOther
        case .blockedByBundlePath: .blockedByBundlePath
        }
    }

    /// 每個 `CodexStateKind` 的**全部**代表值。`.blockedByBundlePath` 這一格
    /// = `RejectionKind.allCases.flatMap(Rejection.samples).map(CodexState.blockedByBundlePath)`
    /// （T04 已備好下層），不是單一代表值——同 `PanelAction.samples` 的既有理由：單一代表值
    /// 時「某個 Rejection 漏了」照樣全綠。窮盡 switch，**不得有 `default`**——理由與 `kind`
    /// 逐字相同：新 case 忘了補這裡，編譯器擋下來；`default: []` 會讓這條定義域推導鏈
    /// 靜默失效。
    public static func samples(_ kind: CodexStateKind) -> [CodexState] {
        switch kind {
        case .unavailable: [.unavailable]
        case .notConnected: [.notConnected]
        case .connected: [.connected]
        case .connectedStalePath: [.connectedStalePath]
        case .occupiedByOther: [.occupiedByOther]
        case .blockedByBundlePath:
            CodexHookPathCheck.RejectionKind.allCases.flatMap(CodexHookPathCheck.Rejection.samples)
                .map(CodexState.blockedByBundlePath)
        }
    }
}

/// `CodexState` 帶 associated value（`.blockedByBundlePath`）不能 `CaseIterable`（D-r，同
/// `PanelActionKind`／`CodexHookPathCheck.RejectionKind` 的既有理由）——這個平行型別供 gate
/// 推導「每一態都要有人接線」（CX19／CX20／CX21）。
public enum CodexStateKind: String, Sendable, CaseIterable {
    case unavailable, notConnected, connected, connectedStalePath, occupiedByOther, blockedByBundlePath
}
