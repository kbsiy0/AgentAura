import Foundation

/// T01 必辦③：G3(a)「內容位元組完全不變」的斷言形狀，供 T03 的
/// `installerRefusesToClobber`（G3）直接沿用。
///
/// **不得用 `try Data(contentsOf:)`**——clobber 後那條路徑是指向目錄的 symlink，
/// `try` 會丟錯而顯示成「拋出未預期錯誤」，不是斷言失敗（A3 實測：before 18 bytes／
/// after nil ⇒ 用 `try?` 才會紅在斷言，而不是紅在一個看起來不相關的 throw）。
enum ClobberAssertionShape {
    enum EntryKind: Equatable { case absent, symlink, directory, regularFile, other(mode_t) }

    /// `Optional<Data>` 快照——讀不到（含「路徑其實是指向目錄的 symlink」）一律 `nil`，
    /// 不 throw。
    static func contentSnapshot(at path: URL) -> Data? {
        try? Data(contentsOf: path)
    }

    /// `lstat` 型別——**不 follow symlink**（用 `lstat` 不是 `stat`），
    /// 因為 clobber 後那顆本身就是 symlink，我們要驗的正是「它變成 symlink 了」。
    static func entryKind(at path: URL) -> EntryKind {
        var st = stat()
        guard lstat(path.path, &st) == 0 else { return .absent }
        switch st.st_mode & S_IFMT {
        case S_IFLNK: return .symlink
        case S_IFDIR: return .directory
        case S_IFREG: return .regularFile
        default: return .other(st.st_mode & S_IFMT)
        }
    }
}
