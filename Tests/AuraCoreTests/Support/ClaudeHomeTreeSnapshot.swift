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
///
/// **`codex-support` T01**：本檔現在只是 `DirectoryTreeSnapshot` 的 skills-realpath
/// 特化（純重構，零行為變更）——通用的 walk／entry／changedPaths 機制搬到那邊，
/// 讓 Codex 側的 gate（CX14／CX32／CX37a／CX37b）可以共用同一套機制，不必抄一份。
enum ClaudeHomeTreeSnapshot {
    typealias Entry = DirectoryTreeSnapshot.Entry

    static func take(claudeHome: URL) -> [String: Entry] {
        DirectoryTreeSnapshot.take(root: claudeHome, alsoResolving: "skills")
    }

    static func changedPaths(before: [String: Entry], after: [String: Entry]) -> Set<String> {
        DirectoryTreeSnapshot.changedPaths(before: before, after: after)
    }
}
