import Foundation

/// T24 D-1 步驟 3／D-6：刪除 `~/.agentaura` 整個狀態目錄——完整移除的一部分。
///
/// **只刪看起來真的是我們自己建的東西**（team-lead 安全界線）：路徑最後一段必須是
/// `.agentaura`、緊接在使用者根目錄之下（不是隨便一個同名子目錄），且用 `lstat`
/// 確認是「真的目錄」——不是被換成指到別處的 symlink（同 `Installer.disconnect()`
/// 只信 `lstat` 的理由，不信 `FileManager.fileExists` 會 follow symlink）。
/// 不符合任一條件、或本來就不存在，一律安靜跳過（D-6：跑第二次不得爆炸）。
public enum StateDirectoryEraser {
    public static func erase(_ url: URL, home: URL) {
        guard isSafeToErase(url, home: home) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// `internal`（不是 `private`）：由 `Tests/AuraCoreTests` 的 `@testable import AuraHookFile`
    /// 直接驗這條判斷本身，不必每次都真的建一顆目錄再 `erase()`。
    static func isSafeToErase(_ url: URL, home: URL) -> Bool {
        guard url.lastPathComponent == ".agentaura" else { return false }
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        guard parent == home.standardizedFileURL.path else { return false }
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return false }   // 不存在／讀不到 → 沒東西可刪
        return (st.st_mode & S_IFMT) == S_IFDIR
    }
}
