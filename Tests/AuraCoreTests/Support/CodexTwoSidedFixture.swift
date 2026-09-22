import Foundation
import AuraHookFile

/// codex-support T01 必辦③（R-8）：同一個暫存根底下同時有 `claudeHome`（含
/// `settings.json` 與 bundle plugin fixture）與 `codexHome`（含 `config.toml`），
/// 兩側都能被各自的 installer 操作——供 CX37a／CX37b 的交錯序列推導使用。
///
/// 重用既有的 `InstallerFixture.make()`（真的 SwiftPM 產物，exec 驗證會真的
/// `.verified`）取得 Claude 側骨架，再在同一個 `root` 底下加一個 `codexHome`。
enum CodexTwoSidedFixture {
    struct Layout {
        let root: URL
        let claudeHome: URL
        let bundlePlugin: URL
        let codexHome: URL
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    static func make() throws -> Layout {
        let installerLayout = try InstallerFixture.make()
        let codexHome = installerLayout.root.appendingPathComponent("codexHome")
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try CodexHomeFixture.seedKnownConfigToml(in: codexHome)
        try "{}".write(to: installerLayout.claudeHome.appendingPathComponent("settings.json"),
                       atomically: true, encoding: .utf8)
        return Layout(root: installerLayout.root, claudeHome: installerLayout.claudeHome,
                      bundlePlugin: installerLayout.bundlePlugin, codexHome: codexHome)
    }
}
