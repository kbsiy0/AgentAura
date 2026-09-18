import Foundation

/// `codex-support` T01：從 `ClaudeHomeTreeSnapshot` 抽出的通用「目錄樹快照」機制
/// （純重構，零行為變更）。`ClaudeHomeTreeSnapshot` 現在是它的 skills-realpath 特化。
///
/// 供 CX14／CX32／CX37a／CX37b 共用：這些 gate 都要對「一棵樹」（`claudeHome` 或
/// `codexHome`）取「邏輯相對路徑 → entry」快照、比對前後差異，只是 root 與是否需要
/// 額外解析某個子項的 symlink 不同。
enum DirectoryTreeSnapshot {
    struct Entry: Equatable {
        let kind: ClobberAssertionShape.EntryKind
        let mode: mode_t
        let size: Int
        let payload: Data?         // 一般檔案的位元組內容；其餘一律 nil
        let symlinkTarget: String? // symlink 的目標；其餘一律 nil
    }

    /// 對 `root` 逐項取 snapshot——字面路徑，不穿透任何子項 symlink 目錄。
    static func take(root: URL) -> [String: Entry] {
        var result: [String: Entry] = [:]
        walk(rootURL: root, prefix: "", into: &result)
        return result
    }

    /// 在 `take(root:)` 之外，若 `root` 底下名為 `childName` 的項目本身是 symlink，
    /// 額外對它 `realpath` 之後的目的地取一份快照，以 `childName` 為邏輯前綴併入結果。
    ///
    /// 這是 `ClaudeHomeTreeSnapshot` 原本內建的「`skills` 自己可能是指到 root 之外的
    /// symlink」處理的通用化——不論 `childName` 存不存在、是不是 symlink、指到 root 內或
    /// 外，這條路徑背後真正落地的內容都要能被看見。若 `childName` 就是 root 內的真目錄，
    /// 這裡會重複掃到 `take(root:)` 已經掃過的東西——字典 key 與 value 都相同，合併沒有
    /// 副作用；只有「`childName` 是外部 symlink」時，才會多掃到字面走訪穿不到的內容。
    static func take(root: URL, alsoResolving childName: String) -> [String: Entry] {
        var result = take(root: root)
        let childURL = root.appendingPathComponent(childName)
        if let resolved = realpath(childURL.path, nil) {
            let resolvedURL = URL(fileURLWithPath: String(cString: resolved))
            free(resolved)
            walk(rootURL: resolvedURL, prefix: childName, into: &result)
        }
        return result
    }

    /// 兩份快照的差異：邏輯路徑聯集裡，值不同（含一邊不存在）的那些 key。
    static func changedPaths(before: [String: Entry], after: [String: Entry]) -> Set<String> {
        let keys = Set(before.keys).union(after.keys)
        return keys.filter { before[$0] != after[$0] }
    }

    private static func walk(rootURL: URL, prefix: String, into result: inout [String: Entry]) {
        guard let e = FileManager.default.enumerator(
            at: rootURL, includingPropertiesForKeys: nil, options: [.producesRelativePathURLs])
        else { return }
        for case let child as URL in e {
            let relative = child.relativePath
            let absolute = rootURL.appendingPathComponent(relative)
            let key = prefix.isEmpty ? relative : "\(prefix)/\(relative)"
            result[key] = entry(at: absolute)
        }
    }

    private static func entry(at url: URL) -> Entry {
        var st = stat()
        guard lstat(url.path, &st) == 0 else {
            return Entry(kind: .absent, mode: 0, size: 0, payload: nil, symlinkTarget: nil)
        }
        switch st.st_mode & S_IFMT {
        case S_IFLNK:
            let target = (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) ?? ""
            return Entry(kind: .symlink, mode: st.st_mode, size: 0, payload: nil, symlinkTarget: target)
        case S_IFDIR:
            return Entry(kind: .directory, mode: st.st_mode, size: 0, payload: nil, symlinkTarget: nil)
        case S_IFREG:
            let data = try? Data(contentsOf: url)
            return Entry(kind: .regularFile, mode: st.st_mode, size: Int(st.st_size),
                        payload: data, symlinkTarget: nil)
        default:
            return Entry(kind: .other(st.st_mode & S_IFMT), mode: st.st_mode, size: 0,
                        payload: nil, symlinkTarget: nil)
        }
    }
}
