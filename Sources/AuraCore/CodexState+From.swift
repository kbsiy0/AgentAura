import Foundation

extension CodexState {
    /// spec §3 判定表（七列，窮盡、零 I/O；**由上而下第一個命中者勝，r4 不動列序**）：
    ///
    /// | # | `codexHomeIsDirectory` | `entryType` | 磁碟 vs `recordedContents` | 磁碟 vs `currentExpectedContents` | `pathRejection` | → |
    /// |---|---|---|---|---|---|---|
    /// | 1 | false | 任意 | — | — | 任意 | `.unavailable` |
    /// | 2 | true | `regularFile` | 兩者非 nil 且逐位元組相等 | 相等 | 任意 | `.connected` |
    /// | 3 | true | `regularFile` | 兩者非 nil 且逐位元組相等 | 不等 | 任意 | `.connectedStalePath` |
    /// | 4 | true | `regularFile` | 其餘（任一 nil／不等／>64KiB 沒讀） | — | 任意 | `.occupiedByOther` |
    /// | 5 | true | `directory`／`symlink`／`otherFile` | — | — | 任意 | `.occupiedByOther` |
    /// | 6 | true | `absent` | — | — | **非 nil** | `.blockedByBundlePath(r)` |
    /// | 7 | true | `absent` | — | — | nil | `.notConnected` |
    ///
    /// 第 2／3 列排在第 6 列之前是刻意的：磁碟上已經有我們的檔時，該講的是那個檔的狀態，
    /// 不是 bundle 路徑判定（R-9：「重新接上」在路徑被拒時不得先刪檔，處置在
    /// `OptionsMenuModel.rows` 與 `performConnectCodex()` 兩處攔，不是靠改這裡的列序）。
    ///
    /// 對 `CodexObservation.EntryType` 窮盡 `switch`，**不得有 `default`**——理由與
    /// `CodexState.kind`／`samples(_:)` 逐字相同。
    public static func from(_ o: CodexObservation, recordedContents: Data?,
                            currentExpectedContents: Data,
                            pathRejection: CodexHookPathCheck.Rejection?) -> CodexState {
        guard o.codexHomeIsDirectory else { return .unavailable }   // 第 1 列

        switch o.entryType {
        case .regularFile:
            guard let disk = o.contents, let recorded = recordedContents, disk == recorded else {
                return .occupiedByOther   // 第 4 列
            }
            return disk == currentExpectedContents ? .connected : .connectedStalePath   // 第 2／3 列
        case .directory, .symlink, .otherFile:
            return .occupiedByOther   // 第 5 列
        case .absent:
            if let pathRejection {
                return .blockedByBundlePath(pathRejection)   // 第 6 列
            }
            return .notConnected   // 第 7 列
        }
    }
}
