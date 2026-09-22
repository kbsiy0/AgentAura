import Foundation
import AuraCore

extension CodexInstaller {
    /// D-q／§4.4：觀測目前的掛載狀態，零判定邏輯——判定住在
    /// `CodexState.from(_:recordedContents:currentExpectedContents:pathRejection:)`（T07）。
    ///
    /// `codexHomeIsDirectory` 用 `stat`（跟隨 symlink）——D-p 要它解析後是不是目錄，
    /// 不是它字面型別；`hooks.json` 的 `entryType` 用 `lstat`（不跟隨最後一段）——
    /// CX15 要看得到「它自己是 symlink」這件事，不是它指向的目標。
    public func probe() -> CodexObservation {
        var homeStat = stat()
        guard stat(codexHome.path, &homeStat) == 0, (homeStat.st_mode & S_IFMT) == S_IFDIR else {
            return CodexObservation(codexHomeIsDirectory: false, entryType: .absent,
                                    contents: nil, displayPath: nil)
        }
        let displayPath = resolveRealPath(codexHome).map { "\($0)/hooks.json" }

        var st = stat()
        guard lstat(hooksJSONURL.path, &st) == 0 else {
            return CodexObservation(codexHomeIsDirectory: true, entryType: .absent,
                                    contents: nil, displayPath: displayPath)
        }
        let entryType = Self.entryType(of: st.st_mode)
        // 只有 regularFile 且 ≤ 64 KiB 才讀（D-q）——我們自己寫的檔 ~2 KB，
        // 超過的不可能是我們寫的，讀進來也沒有意義，只是白花時間跟記憶體。
        guard entryType == .regularFile, st.st_size <= Self.maxReadableBytes else {
            return CodexObservation(codexHomeIsDirectory: true, entryType: entryType,
                                    contents: nil, displayPath: displayPath)
        }
        return CodexObservation(codexHomeIsDirectory: true, entryType: entryType,
                                contents: readContents(at: hooksJSONURL.path), displayPath: displayPath)
    }

    /// D-q：64 KiB，含端點（`≤`）。
    static var maxReadableBytes: Int { 64 * 1024 }

    private func readContents(at path: String) -> Data? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        return try? FileHandle(fileDescriptor: fd, closeOnDealloc: false).readToEnd()
    }

    private func resolveRealPath(_ url: URL) -> String? {
        guard let cstr = realpath(url.path, nil) else { return nil }
        defer { free(cstr) }
        return String(cString: cstr)
    }

    static func entryType(of mode: mode_t) -> CodexObservation.EntryType {
        switch mode & S_IFMT {
        case S_IFREG: return .regularFile
        case S_IFDIR: return .directory
        case S_IFLNK: return .symlink
        default: return .otherFile
        }
    }
}
