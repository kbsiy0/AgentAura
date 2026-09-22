import Foundation

/// 產生 hook payload 的來源 agent —— Claude Code 或 Codex CLI（spec §3／D-a／D-b）。
///
/// 磁碟上的 `agent` 欄位是 `String?`（見 `SessionSnapshot.agent`），**不是**這個 enum ——
/// `Codable` 對「未知 rawValue 的 enum」是整包解碼失敗，未來多一種 agent 時，舊版 app
/// 讀到的行為會是「那個 session 從面板整個消失」（D-a，同 `outstandingSubagents` 的既有理由）。
/// 這個 enum 只在 AuraCore 的邊界（`init(stored:)`）把 `String?` 解析成型別化的值。
///
/// 安全預設是 `.claude`（D-b）：未知值與 `nil` 一律落回 `.claude`，**保守失敗**——
/// 寧可少一個「Codex」標籤（`.claude` 不顯示標籤，見 `label`），也不可把 Codex 的列
/// 誤標成 Claude 的。
///
/// 這跟 `Language`（見該檔 doc comment）「一律不給預設值、漏傳即編譯錯誤」的紀律**刻意不同**：
/// `Language` 守的是我們自己傳進去的**顯示參數**，漏傳是程式錯誤，該讓編譯器擋下來；
/// `Agent` 解析的是**外部輸入**（舊版磁碟上沒有這個欄位的資料、未來未知的 agent 名、
/// 手誤或手寫錯的 `--agent` 參數）——這類輸入本來就會出現「認不得」的值，沒有安全預設
/// 就會變成整個 session 從面板消失，或是要求呼叫端自己 throw／崩潰。
public enum Agent: String, Sendable, Equatable, CaseIterable {
    case claude
    case codex

    /// 從磁碟上的 `agent` 欄位（`SessionSnapshot.agent`，`String?`）解析。
    /// `nil` 或任何未知字串（含大小寫不符）一律落回 `.claude`（D-b）。
    public init(stored: String?) {
        switch stored {
        case Agent.codex.rawValue: self = .codex
        default: self = .claude
        }
    }

    /// 寫回磁碟時要用的字串。`.claude` 回 `nil` —— Claude 路徑的狀態檔位元組
    /// 與加上這個欄位之前**完全相同**（D-c／CX9）。`.codex` 回 `"codex"`。
    public var storedRawValue: String? {
        switch self {
        case .claude: nil
        case .codex: rawValue
        }
    }

    /// 面板列上顯示的標籤。`.claude` 回 `nil`（不顯示任何標籤）；`.codex` 回 `"Codex"`。
    ///
    /// 「Codex」是產品名，刻意**不**進 `L10n*` 字串表 —— 這是唯一在兩種語言下都該原樣
    /// 顯示的字面值，翻譯反而是錯的（同 D-l 的列位置決定）。
    public var label: String? {
        switch self {
        case .claude: nil
        case .codex: "Codex"
        }
    }
}

/// 解析 `aura-hook` 的 `--agent` 命令列參數（D-d／spec §4.1）。
///
/// 支援 `--agent codex`（下一個 argv 元素當值）與 `--agent=codex`（同一個元素帶等號）
/// 兩種寫法；由左至右取**第一個**匹配者，大小寫敏感；不匹配（未知值、缺值、多餘參數、
/// 或整個 argv 裡沒有 `--agent`）一律 `.claude`。**絕不 throw、絕不寫 stdout／stderr** ——
/// `aura-hook` 的觀測性絕不可干擾呼叫它的 agent（CLAUDE.md invariant）。
public enum AgentArgument {
    public static func agent(from argv: [String]) -> Agent {
        for (index, element) in argv.enumerated() {
            if let inlineValue = inlineValue(in: element) {
                return Agent(stored: inlineValue)
            }
            if element == "--agent" {
                let valueIndex = index + 1
                guard valueIndex < argv.count else { return .claude }
                return Agent(stored: argv[valueIndex])
            }
        }
        return .claude
    }

    /// `--agent=<值>` 寫法：回傳等號後的字串；不是這個寫法回 `nil`。
    private static func inlineValue(in element: String) -> String? {
        let prefix = "--agent="
        guard element.hasPrefix(prefix) else { return nil }
        return String(element.dropFirst(prefix.count))
    }
}
