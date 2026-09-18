import Foundation

/// `CodexInstaller.probe()`（`AuraHookFile`，T06）的觀測結果。純資料、零判定邏輯——
/// 判定住在 `CodexState.from(_:recordedContents:currentExpectedContents:pathRejection:)`（T07）。
///
/// 同 `LinkObservation` 的既有分工：這裡只回答「磁碟上有什麼」，不回答「該顯示哪一態」。
public struct CodexObservation: Equatable, Sendable {
    /// `codexHome`（`~/.codex`）本身是否**解析**成目錄——`stat`（跟隨 symlink），
    /// 不是 `lstat`：D-p 要求「`~/.codex` 自己是 symlink 時不拒絕」，判的是它解析後
    /// 落在哪裡，不是它字面上是什麼型別。
    public let codexHomeIsDirectory: Bool
    /// `hooks.json` 這個路徑本身的型別，`lstat` 判定（不 follow 最後一段）。
    public let entryType: EntryType
    /// 只有 `entryType == .regularFile` 且大小 ≤ 64 KiB（D-q）才非 nil。
    public let contents: Data?
    /// 只給 UI 顯示，不參與判定——`realpath(codexHome)/hooks.json`。
    public let displayPath: String?

    public init(codexHomeIsDirectory: Bool, entryType: EntryType, contents: Data?, displayPath: String?) {
        self.codexHomeIsDirectory = codexHomeIsDirectory
        self.entryType = entryType
        self.contents = contents
        self.displayPath = displayPath
    }

    /// 窮盡定義域，供 T07 的 `CodexState.from` 逐格判定（無 `default`）。`otherFile`
    /// 同 `LinkObservation.EntryType` 的既有理由：FIFO／device 等不可能出現在這裡，
    /// 但型別不該假裝它不能發生。
    public enum EntryType: String, Sendable, CaseIterable {
        case absent, regularFile, directory, symlink, otherFile
    }
}
