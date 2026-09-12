import Testing
import Foundation
@testable import AuraHookFile

/// T03 G2：`installerTouchesOnlyAllowedPaths`（spec §6.3，「本 change 最重要的一條」）。
/// connect＋disconnect 前後對 `realpath(<claudeHome>/skills)` ＋ claudeHome 整棵樹取
/// `ClaudeHomeTreeSnapshot`，容許差異集合恰為 `{skills（若原不存在）, skills/agentaura}`。
@Suite("Installer 只碰允許的路徑（G2）")
struct InstallerPathScopeTests {

    @Test("全新 claudeHome：connect 後差異恰為 {skills, skills/agentaura}；disconnect 後只剩 {skills}（新建的空目錄留著）")
    func connectAndDisconnectTouchOnlyAllowedPaths() async throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        try "{}".write(to: layout.claudeHome.appendingPathComponent("settings.json"),
                       atomically: true, encoding: .utf8)
        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)

        let before = ClaudeHomeTreeSnapshot.take(claudeHome: layout.claudeHome)
        _ = try await SpawnGate.shared.run {
            try installer.connect(force: false, translocated: false, inDownloads: false)
        }
        let afterConnect = ClaudeHomeTreeSnapshot.take(claudeHome: layout.claudeHome)

        let connectDelta = ClaudeHomeTreeSnapshot.changedPaths(before: before, after: afterConnect)
        #expect(connectDelta == ["skills", "skills/agentaura"], """
            connect() 後的差異應恰為 {skills, skills/agentaura}（skills 原不存在），實際：\(connectDelta.sorted())
            """)
        #expect(before["settings.json"] == afterConnect["settings.json"],
                "settings.json 的位元組必須完全不變——D3/R6「絕不碰 settings.json」")

        try installer.disconnect()
        let afterDisconnect = ClaudeHomeTreeSnapshot.take(claudeHome: layout.claudeHome)
        let disconnectDelta = ClaudeHomeTreeSnapshot.changedPaths(before: afterConnect, after: afterDisconnect)
        #expect(disconnectDelta == ["skills/agentaura"], """
            disconnect() 只移除 agentaura 這個 symlink，skills 目錄本身留著（是空目錄，不是問題）；
            實際差異：\(disconnectDelta.sorted())
            """)
        #expect(before["settings.json"] == afterDisconnect["settings.json"])
    }

    /// T01 必辦②的正式用途：`skills` 自己是指到 claudeHome **之外**的 symlink。
    /// 這是 G2 最重要的 fixture——實測那種設定下寫入落在外面，claudeHome 的樹狀
    /// 元組若只用字面路徑取 snapshot 會完全沒變 ⇒ 舊寫法在這裡會全綠地放過真違規。
    @Test("skills 本身是指到 claudeHome 之外的 symlink：connect 後 claudeHome 的字面樹完全不變，寫入落在 realpath(skills) 底下")
    func connectThroughExternalSkillsSymlinkOnlyTouchesResolvedLocation() async throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        let symlinkLayout = try ClaudeHomeSkillsSymlinkFixture.make()
        defer { try? FileManager.default.removeItem(at: symlinkLayout.claudeHome.deletingLastPathComponent()) }
        // 用 fixture 提供的 claudeHome（skills 已經是指到外面的 symlink），但沿用
        // layout 的 bundlePlugin（真的能跑的二進位）。
        let installer = InstallerFixture.installer(claudeHome: symlinkLayout.claudeHome, bundlePluginURL: layout.bundlePlugin)

        let before = ClaudeHomeTreeSnapshot.take(claudeHome: symlinkLayout.claudeHome)
        _ = try await SpawnGate.shared.run {
            try installer.connect(force: false, translocated: false, inDownloads: false)
        }
        let after = ClaudeHomeTreeSnapshot.take(claudeHome: symlinkLayout.claudeHome)

        // skills 自己（symlink 目標）必須完全不變——它本來就存在，connect() 不該碰它。
        #expect(before["skills"] == after["skills"], "skills 這個 symlink 本身（指到 claudeHome 外）不得被 connect() 改動")

        let delta = ClaudeHomeTreeSnapshot.changedPaths(before: before, after: after)
        #expect(delta == ["skills/agentaura"], """
            skills 已存在時，唯一該出現的差異是 skills/agentaura（不含 "skills" 本身，
            因為它原本就在）；實際：\(delta.sorted())
            """)

        // 對照組：external-skills 目錄底下真的多了一個 agentaura symlink——證明寫入
        // 真的落在 realpath(skills)，不是憑空消失。
        #expect(FileManager.default.fileExists(
            atPath: symlinkLayout.externalSkillsDir.appendingPathComponent("agentaura").path))
    }
}
