import Testing
import Foundation
import AuraHookFile

/// T11（CX29；T11c m1 擴大）：`SECURITY.md` **與兩份 README** 都必須列出我們會寫的 Codex
/// 路徑——同一條資訊本來就重複寫在三個地方（README 的「What it does to your Mac」、
/// README.zh-TW 的中文對應段、`SECURITY.md` 的「What this tool can do on your machine」），
/// 這是使用者評估風險時第一個要看的清單，漏了一條寫入路徑就是文件說謊。
///
/// **T11c m1（spec-reviewer 實測）**：T11 原本只守 `SECURITY.md`，doc comment 裡雖然寫著
/// 「同 README.md 的…」卻沒有真的守它——reviewer 把 `.codex/hooks.json` 從 SECURITY.md
/// **與** README.md 兩邊都刪掉，這條 gate 仍然只紅 1 條。改成對三份文件參數化，內容
/// 本來就都在（T11 寫文件時三處都加了），這裡補的是**守衛**，不是新增內容。
///
/// **字面來自生產常數，不手打**（同 CX6／CX9 的既有理由：手打的字面會跟生產程式碼 drift）：
/// 從 `CodexInstaller.production().hooksJSONURL` 反推 `.codex/hooks.json` 這個相對片段
/// ——最後兩個路徑元件——而不是自己重新拼一份 `"~/.codex/hooks.json"` 字串常數。
@Suite("SECURITY.md 與兩份 README 都列出 Codex 會寫的路徑（CX29）")
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

    @Test("文件含 Codex hooks.json 這個路徑", arguments: ["SECURITY.md", "README.md", "README.zh-TW.md"])
    func docListsCodexHooksPath(fileName: String) throws {
        let text = try String(
            contentsOf: Gate.repoRoot().appendingPathComponent(fileName), encoding: .utf8)
        let expected = Self.expectedRelativePath()
        #expect(text.contains(expected), """
            \(fileName) 沒有提到「\(expected)」——這是使用者評估風險時要看的寫入路徑清單，
            漏了任何一份都是文件說謊。
            """)
    }
}
