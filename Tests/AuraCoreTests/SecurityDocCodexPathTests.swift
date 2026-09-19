import Testing
import Foundation
import AuraHookFile

/// T11（CX29）：`SECURITY.md` 必須列出我們會寫的 Codex 路徑——同 README.md 的
/// 「What it does to your Mac」／`SECURITY.md` 自己的「What this tool can do on your
/// machine」，這是使用者評估風險時第一個要看的清單，漏了一條寫入路徑就是文件說謊。
///
/// **字面來自生產常數，不手打**（同 CX6／CX9 的既有理由：手打的字面會跟生產程式碼 drift）：
/// 從 `CodexInstaller.production().hooksJSONURL` 反推 `.codex/hooks.json` 這個相對片段
/// ——最後兩個路徑元件——而不是自己重新拼一份 `"~/.codex/hooks.json"` 字串常數。
@Suite("SECURITY.md 列出 Codex 會寫的路徑（CX29）")
struct SecurityDocCodexPathTests {

    /// `~/.codex/hooks.json` 的相對片段（`.codex/hooks.json`），從生產 URL 反推。
    static func expectedRelativePath() -> String {
        let url = CodexInstaller.production().hooksJSONURL
        return "\(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent)"
    }

    @Test("反推出來的相對路徑就是 .codex/hooks.json（自我檢查，不是本條 gate 的主張）")
    func expectedRelativePathIsCodexHooksJSON() {
        #expect(Self.expectedRelativePath() == ".codex/hooks.json")
    }

    @Test("SECURITY.md 含 Codex hooks.json 這個路徑")
    func securityDocListsCodexHooksPath() throws {
        let text = try String(
            contentsOf: Gate.repoRoot().appendingPathComponent("SECURITY.md"), encoding: .utf8)
        let expected = Self.expectedRelativePath()
        #expect(text.contains(expected), """
            SECURITY.md 沒有提到「\(expected)」——「What this tool can do on your machine」
            必須列出這條 Codex 會寫的路徑，使用者才能完整評估風險。
            """)
    }
}
