import Testing
import Foundation

/// T01 必辦②的自我測試：驗證 `ClaudeHomeSkillsSymlinkFixture` 建出來的佈局
/// 真的有 A2 實測描述的那個性質——用真的 `lstat`／`realpath`，不是猜。
/// **這條合理地是 GREEN**：它驗的是 fixture 自己的性質（純 Foundation／POSIX 呼叫），
/// 不是還沒寫的 `Installer`／G2 邏輯。
@Suite("ClaudeHomeSkillsSymlinkFixture 自我驗證")
struct ClaudeHomeSkillsSymlinkFixtureTests {

    @Test("skills 本身是 symlink，且 realpath(skills) 落在 claudeHome 之外")
    func skillsSymlinkPointsOutsideClaudeHome() throws {
        let layout = try ClaudeHomeSkillsSymlinkFixture.make()
        defer { try? FileManager.default.removeItem(at: layout.claudeHome.deletingLastPathComponent()) }

        let skillsPath = layout.claudeHome.appendingPathComponent("skills").path
        var st = stat()
        #expect(lstat(skillsPath, &st) == 0, "lstat(skills) 應成功")
        #expect((st.st_mode & S_IFMT) == S_IFLNK, "lstat(skills) 應回 symlink，實際 mode=\(st.st_mode)")

        let resolved = URL(fileURLWithPath: skillsPath).resolvingSymlinksInPath().standardizedFileURL.path
        let claudeHomeResolved = layout.claudeHome.resolvingSymlinksInPath().standardizedFileURL.path
        #expect(!resolved.hasPrefix(claudeHomeResolved), """
            realpath(skills) 應落在 claudeHome 之外，實際 \(resolved)（claudeHome=\(claudeHomeResolved)）
            """)
        #expect(resolved.hasPrefix(layout.externalSkillsDir.resolvingSymlinksInPath().standardizedFileURL.path),
                "應解析到 externalSkillsDir")
    }

    /// 對照：字面路徑（不解析）版本的 snapshot 會漏看這個目錄——這正是 A2 要修的 G2 破洞。
    @Test("字面路徑列出 claudeHome 樹看不到 external-skills 底下的內容（對照：這就是舊版 G2 的破洞）")
    func literalPathTraversalMissesExternalContent() throws {
        let layout = try ClaudeHomeSkillsSymlinkFixture.make()
        defer { try? FileManager.default.removeItem(at: layout.claudeHome.deletingLastPathComponent()) }

        try "marker".write(to: layout.externalSkillsDir.appendingPathComponent("agentaura"),
                           atomically: true, encoding: .utf8)

        guard let e = FileManager.default.enumerator(
            at: layout.claudeHome, includingPropertiesForKeys: nil,
            options: [.producesRelativePathURLs]) else {
            Issue.record("enumerator 建不出來")
            return
        }
        // `FileManager` 的 directory enumerator 預設不穿過 symlink 目錄往下列——
        // 只看得到 `skills` 這個 symlink 本身，看不到它背後 external-skills/agentaura。
        let names = e.compactMap { ($0 as? URL)?.lastPathComponent }
        #expect(names.contains("skills"), "至少要列到 skills 這個 symlink 本身")
        #expect(!names.contains("agentaura"), """
            字面樹狀列舉不該穿透 symlink 看到 external-skills/agentaura——
            這正是「claudeHome 的樹完全沒變」讓舊版 G2 全綠的破洞
            """)
    }
}
