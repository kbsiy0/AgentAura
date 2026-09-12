import Foundation

/// T03 G2（`installerTouchesOnlyAllowedPaths`）共用：對 `claudeHome` **整棵樹**（不穿透
/// symlink 目錄——只看 `skills`這個 symlink 本身）＋ `realpath(claudeHome/skills)` 的內容
/// （T01 必辦②：`skills` 自己可能是指到 claudeHome **之外**的 symlink，這時寫入落在外面，
/// 用字面路徑取 snapshot 會看不到——`ClaudeHomeSkillsSymlinkFixtureTests` 已經證實這個破洞）
/// 各取一份，合併成一組「邏輯相對路徑」→ entry 的字典，供前後比對差異。
///
/// `skills` 解析後的內容一律以 `"skills/"` 為邏輯前綴，不論它實際落在哪裡——這樣
/// 「容許差異集合恰為 {skills, skills/agentaura}」才能講同一種座標系，不管 `skills`
/// 是不是外部 symlink。
enum ClaudeHomeTreeSnapshot {
    struct Entry: Equatable {
        let kind: ClobberAssertionShape.EntryKind
        let mode: mode_t
        let size: Int
        let payload: Data?         // 一般檔案的位元組內容；其餘一律 nil
        let symlinkTarget: String? // symlink 的目標；其餘一律 nil
    }

    static func take(claudeHome: URL) -> [String: Entry] {
        var result: [String: Entry] = [:]
        walk(rootURL: claudeHome, prefix: "", into: &result)

        let skillsURL = claudeHome.appendingPathComponent("skills")
        if let resolved = realpath(skillsURL.path, nil) {
            let resolvedURL = URL(fileURLWithPath: String(cString: resolved))
            free(resolved)
            // 若 skills 就是 claudeHome 底下的真目錄，這裡會重複掃到上面已經掃過的東西——
            // 字典 key 與 value 都相同，合併沒有副作用；只有「skills 是外部 symlink」時，
            // 這裡才會掃到第一次 walk 穿不到的內容。
            walk(rootURL: resolvedURL, prefix: "skills", into: &result)
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
