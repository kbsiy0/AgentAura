import Foundation

/// T01 必辦②：G2 的 snapshot 要改對 `realpath(<claudeHome>/skills)` 取，不是字面路徑
/// ——A2 實測：`skills` 自己可能是一顆指到 claudeHome **之外**的 symlink（Claude Code
/// 自己也會這樣設定同步 skills），這時 `lstat` 穿過父層回 absent、寫入落在外面，
/// 而 claudeHome 的樹狀元組完全沒變 ⇒ 字面路徑版本的 G2 會全綠。這個 helper 建出
/// 那種佈局，供 T03 的 `installerTouchesOnlyAllowedPaths`（G2）直接使用。
enum ClaudeHomeSkillsSymlinkFixture {
    struct Layout {
        let claudeHome: URL
        /// `claudeHome` 之外、`skills` 實際指過去的地方。
        let externalSkillsDir: URL
    }

    /// 建一個 `<tmp>/claudeHome/skills` 本身是指到 `<tmp>/external-skills`（claudeHome 之外）
    /// 的 symlink 的佈局。
    static func make() throws -> Layout {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aura-t01-skills-symlink-\(UUID().uuidString)")
        let claudeHome = root.appendingPathComponent("claudeHome")
        let external = root.appendingPathComponent("external-skills")
        try FileManager.default.createDirectory(at: claudeHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: claudeHome.appendingPathComponent("skills"), withDestinationURL: external)
        return Layout(claudeHome: claudeHome, externalSkillsDir: external)
    }
}
