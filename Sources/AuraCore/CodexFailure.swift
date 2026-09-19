/// `CodexInstaller.connect`／`disconnect`（`AuraHookFile`，T06）失敗的明確結果
/// （spec §2／§4.4，七個 case）。同 `InstallerFailure` 的既有分工：住 `AuraCore`，
/// 因為文案（`L10nCodex`，T09）要窮盡推導這個型別，不該只有 `AuraHookFile` 看得到。
public enum CodexFailure: Error, Equatable {
    /// `codexHome`（`~/.codex`）不是目錄——**不建立它**。
    case codexHomeMissing
    /// `hooks.json` 已存在（任何型別：普通檔／目錄／symlink／斷鏈 symlink）——
    /// 四種佔用形狀實測**一律** `EEXIST`（D-i）。
    case alreadyExists
    /// `open`（建立）／寫入／`unlink`（刪除）失敗（權限、磁碟滿……），帶 errno。
    /// **m4（spec-reviewer 2026-09-18）：涵蓋三種 syscall 失敗，文案不要寫死「寫入」**
    /// ——`unlinkIfIdentityUnchanged(_:)` 的 `unlink` 失敗也重用這個 case，使用者
    /// 實際遇到的情境可能是「移除掛載時」而不是「接上時」。
    case writeFailed(Int32)
    /// `disconnect` 判定「這不是我們寫的」：內容不符、`(dev,ino)` 換過、或型別不是
    /// 普通檔（symlink／目錄）——一律不刪。
    case notOurs
    /// `disconnect` 連讀都讀不到（`open` 失敗，非 absent 非 symlink 的其他 errno，
    /// 通常是權限），帶 errno。
    case unreadable(Int32)
    /// App 是 translocated 或在 `~/Downloads`（R-5）。
    case mustMoveToApplications
    /// hook 路徑含 shell／JSON 都會出問題的字元；帶的是**第一個**命中的那一個（R-5）。
    case unsupportedPathCharacter(Character)
}

extension CodexFailure {
    /// R-5：`CodexHookPathCheck.Rejection` → `CodexFailure` 的唯一映射。三個消費者
    /// （路由層／`performConnectCodex()` 前置 guard／`CodexInstaller.connect` 第一行）
    /// 都呼叫同一個 `CodexHookPathCheck.rejection(...)`，這裡只是把它的輸出轉成
    /// 執行層要拋出的錯誤型別，不是另一份判定。
    public init(rejection: CodexHookPathCheck.Rejection) {
        switch rejection {
        case .mustMoveToApplications: self = .mustMoveToApplications
        case .unsupportedCharacter(let character): self = .unsupportedPathCharacter(character)
        }
    }
}
