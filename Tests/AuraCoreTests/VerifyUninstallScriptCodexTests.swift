import Testing
import Foundation
import AuraCore

/// T11（CX27）：`scripts/verify-uninstall.sh` 第 7 項——`${CODEX_HOME:-$HOME/.codex}/hooks.json`
/// 存在**且**含 `--agent codex` → FAIL（D-o：內容判準，因為腳本跑的時候 persistent domain
/// 已清空，沒有其他地方能問）。
///
/// **判準是那一行的 PASS/FAIL，不是整體 exit code**（spec §4.5）：第 1–6 項查**真實** `$HOME`，
/// 在任何一台開發機上本來就會 FAIL、整支腳本本來就非零退出——用整體 exit code 當判準，
/// mutation（拿掉第 7 項）不會讓這條測試變紅，因為 exit code 早就非零了。所以這裡一律用
/// `--only 7` 把其他六項連同 `osascript`／`sfltool dumpbtm` 一起跳過，只看第 7 項那個區塊
/// 印出的 ✓／✗。
///
/// **輸入用真正的產生器輸出**（`CodexHooksJSON.json(hookBinaryPath:)`），不是手打的假 JSON——
/// 同 CX31、CX6 的既有理由：手打的字面會跟產生器的實際形狀 drift。
///
/// **不經過 `SpawnGate`**：`--only 7` 純粹是本機檔案系統判斷（`[ -f ]` ＋ `grep`），
/// 不呼叫 `osascript`／`sfltool`，執行時間是毫秒級——跟 `SpawnGateCoverageSourceScanTests`
/// 明確排除在外的 `swiftc`／`lipo`／`claude` 呼叫同一類，不是這個 change 要序列化的
/// 「真的 spawn aura-hook」那個類別。
@Suite("verify-uninstall.sh 第 7 項偵測自己寫的 Codex hook（CX27）")
struct VerifyUninstallScriptCodexTests {

    static func scriptURL() -> URL {
        Gate.repoRoot().appendingPathComponent("scripts/verify-uninstall.sh")
    }

    /// 跑腳本，注入 `CODEX_HOME`、帶 `--only 7`，回傳完整 stdout（含 stderr，合流方便除錯）。
    static func run(codexHome: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Self.scriptURL().path, "--only", "7"]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["CODEX_HOME": codexHome.path]) { _, new in new }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// 第 7 項那一段輸出——從含 `"== 7."` 的那一行到下一個 `"=="` 開頭的行之前（或檔尾）。
    /// 解析失敗（腳本輸出裡完全沒有這個區塊）大聲丟錯，不是安靜回空字串。
    static func item7Block(_ output: String) throws -> String {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: { $0.contains("== 7.") }) else {
            throw Gate.GateFailure("輸出裡找不到「== 7.」這個區塊，實際輸出：\n\(output)")
        }
        let rest = lines[(start + 1)...]
        let end = rest.firstIndex(where: { $0.hasPrefix("==") }) ?? lines.endIndex
        return lines[start..<end].joined(separator: "\n")
    }

    @Test("hooks.json 存在且含 --agent codex（真正的產生器輸出）→ 第 7 項 FAIL")
    func detectsOurCodexHook() throws {
        try Gate.withTemporaryDirectory { dir in
            let json = CodexHooksJSON.json(hookBinaryPath: "/usr/bin/true")
            try json.write(to: dir.appendingPathComponent("hooks.json"))
            let block = try Self.item7Block(Self.run(codexHome: dir))
            #expect(block.contains("✗"), "應該判定 FAIL，實際輸出：\n\(block)")
            #expect(!block.contains("✓"), "不該同時出現 PASS 標記，實際輸出：\n\(block)")
        }
    }

    @Test("hooks.json 不存在 → 第 7 項 PASS")
    func passesWhenAbsent() throws {
        try Gate.withTemporaryDirectory { dir in
            let block = try Self.item7Block(Self.run(codexHome: dir))
            #expect(block.contains("✓"), "應該判定 PASS，實際輸出：\n\(block)")
            #expect(!block.contains("✗"), "不該出現 FAIL 標記，實際輸出：\n\(block)")
        }
    }

    @Test("hooks.json 存在但不是我們的（沒有 --agent codex）→ 第 7 項仍 PASS（不是我們寫的不算殘留）")
    func passesWhenSomeoneElsesHookExists() throws {
        try Gate.withTemporaryDirectory { dir in
            try Data("{\"hooks\":{}}".utf8).write(to: dir.appendingPathComponent("hooks.json"))
            let block = try Self.item7Block(Self.run(codexHome: dir))
            #expect(block.contains("✓"), "別人的 hooks.json 不該被判成我們的殘留，實際輸出：\n\(block)")
        }
    }

    @Test("--only 7 不會跑其他六項（不印出 == 1. 這種區塊，也不會卡在 sfltool 上）")
    func onlyRunsItemSeven() throws {
        try Gate.withTemporaryDirectory { dir in
            let output = try Self.run(codexHome: dir)
            #expect(!output.contains("== 1."), "--only 7 不該印出其他項目：\n\(output)")
            #expect(output.contains("== 7."), "--only 7 至少要印出第 7 項：\n\(output)")
        }
    }
}
