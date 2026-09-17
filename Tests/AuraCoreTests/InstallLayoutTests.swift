import Testing
import Foundation

@Suite("安裝佈局")
struct InstallLayoutTests {

    static func repoRoot() -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        while dir.pathComponents.count > 1 {
            dir = dir.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir
            }
        }
        fatalError("找不到 Package.swift")
    }

    /// 從 `hooks.json` 的 command 字串**推導**出應存在的路徑，不寫死。
    ///
    /// 若寫死 `plugin/bin/aura-hook`，有人把 hooks.json 改成
    /// `${CLAUDE_PLUGIN_ROOT}/exec/aura-hook` 並同步改掉 Task 13 的字面值時，
    /// 這條測試仍會檢查舊路徑 —— 全綠但產品靜默失效。這正是 前一個專案 的失效方式。
    static func expectedBinaryPath() throws -> URL {
        // **不在這裡再解析一次 `hooks.json`。**
        //
        // 這裡原本有第二份解析器，於是 T13 把事件包進 `"hooks"` 物件時它沒同步，
        // 四條測試裡三條變紅。紅是好事，但代價是兩份程式碼要靠人記得一起改 ——
        // 那正是「接縫」的定義。改成直接用 `PluginWiringTests.entries()`，
        // 全 repo 只留一份 hooks.json 解析器。
        let commands = Set(try PluginWiringTests.entries().compactMap { $0.entry["command"] as? String })
        #expect(commands.count == 1, "全部 hook 應指向同一個 command：\(commands.sorted())")
        let command = try #require(commands.first)
        // command 是加了引號的（官方慣例，$HOME 含空白才不會裂開），先剝掉
        let unquoted = command.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        // 安裝後 plugin 根目錄就是 repo 的 plugin/
        let relative = unquoted.replacingOccurrences(of: "${CLAUDE_PLUGIN_ROOT}/", with: "plugin/")
        return repoRoot().appendingPathComponent(relative)
    }

    @Test("hooks.json 指向的路徑，在 repo 的 plugin 目錄下真的存在且可執行")
    func pluginBinaryIsInPlace() throws {
        let bin = try Self.expectedBinaryPath()
        // #expect 的訊息參數型別是 `Comment`（ExpressibleByStringInterpolation），
        // 不能用字串串接 —— `+` 會讓它變成 String，編譯錯誤（實測）。
        #expect(FileManager.default.isExecutableFile(atPath: bin.path),
                "\(bin.path) 不存在或不可執行。先跑 scripts/build-plugin.sh。這條擋的正是 前一個專案 留下死 hook 的失效方式")
    }

    @Test("plugin 的 aura-hook 是 universal binary（arm64 + x86_64）")
    func binaryIsUniversal() throws {
        let bin = try Self.expectedBinaryPath()
        try #require(FileManager.default.isExecutableFile(atPath: bin.path))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
        p.arguments = ["-archs", bin.path]
        let pipe = Pipe(); p.standardOutput = pipe
        try p.run(); p.waitUntilExit()
        let archs = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(archs.contains("arm64"), "archs=\(archs)")
        #expect(archs.contains("x86_64"), "開源給別人用，Intel Mac 也要能跑。archs=\(archs)")
    }

    @Test("plugin 的 aura-hook 真的能處理 payload")
    func pluginBinaryWorks() async throws {
        let bin = try Self.expectedBinaryPath()
        try #require(FileManager.default.isExecutableFile(atPath: bin.path))
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-install-\(UUID().uuidString)/sessions")

        // T10b：真的 spawn aura-hook，經過 SpawnGate。
        let status = try await SpawnGate.shared.run { () throws -> Int32 in
            let p = Process()
            p.executableURL = bin
            p.environment = ProcessInfo.processInfo.environment.merging(
                ["AGENTAURA_ROOT": root.path]) { _, new in new }
            let pipe = Pipe(); p.standardInput = pipe
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try p.run()
            pipe.fileHandleForWriting.write(Data(
                #"{"hook_event_name":"PermissionRequest","session_id":"inst1","tool_name":"Bash"}"#.utf8))
            try pipe.fileHandleForWriting.close()
            p.waitUntilExit()
            return p.terminationStatus
        }

        #expect(status == 0)
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("inst1.json").path),
            "安裝用的二進位必須真的能寫狀態檔，不只是存在")
    }

    /// 掃描對象**從磁碟推導**（`docs/INSTALL*.md`），不寫死單一檔名。
    ///
    /// 2026-09-16：安裝文件拆成中英兩份（`INSTALL.md` 英文、`INSTALL.zh-TW.md` 中文）。
    /// 原本這條只讀 `docs/INSTALL.md` 且斷言中文標題「## 完整移除」——拆檔之後，
    /// **英文那份少寫一半指令也不會有人紅**，而中文那份根本不在掃描範圍裡。
    /// 改成逐一掃每一份安裝文件，並且只斷言**真正的指令**：語言會變，指令不會。
    /// （同一份 doc comment 底下原本就寫過這個道理：代理字串會 drift，指令不會。）
    @Test("每一份 INSTALL 文件都要有真正的安裝與移除指令（R6：一步安裝、一步移除）")
    func installDocHasUninstall() throws {
        let docsDir = Self.repoRoot().appendingPathComponent("docs")
        let installDocs = try FileManager.default.contentsOfDirectory(atPath: docsDir.path)
            .filter { $0.hasPrefix("INSTALL") && $0.hasSuffix(".md") }
            .sorted()
        #expect(installDocs.count >= 2, """
            只找到 \(installDocs.count) 份安裝文件（\(installDocs.joined(separator: "、")))——
            中英雙語各要有一份；少一份代表某個語言的讀者沒有文件可看。
            """)

        for name in installDocs {
            let doc = try String(contentsOf: docsDir.appendingPathComponent(name), encoding: .utf8)
            #expect(doc.contains("rm ~/.claude/skills/agentaura"), """
                \(name) 沒寫明真正的移除指令（skills-dir 掛載就是刪那個 symlink）
                """)
            // 斷言**完整的指令列**，不是 `ln -sfn` 這個片段。
            // mutation 實測：只比對片段時，把真正的指令整行刪掉仍然全綠——因為文件裡
            // 另有一句「想凍結版本就用 cp -R 取代 ln -sfn」只是**提到**它。
            // 那正是本檔上面那段註解警告過的代理字串，只是這次換了一個位置復發。
            #expect(doc.contains("""
                ln -sfn "$PWD/plugin" ~/.claude/skills/agentaura
                """), """
                \(name) 沒有完整的掛載指令 `ln -sfn "$PWD/plugin" ~/.claude/skills/agentaura`，
                或與實際機制不一致
                """)
        }
    }

    /// 保留舊的單檔斷言形狀給英文主文件，內容改為語言中性的錨點。
    @Test("英文 INSTALL.md 仍是主文件（README 連向它）")
    func englishInstallDocIsPrimary() throws {
        let doc = try String(contentsOf: Self.repoRoot().appendingPathComponent("docs/INSTALL.md"),
                             encoding: .utf8)
        // 斷言**真正的移除指令**，不是一個代理字串。
        //
        // 這裡原本斷言 `doc.contains("plugin uninstall")`。安裝方式改成 skills-dir
        // 掛載之後，那個字串只剩在一句「**沒有** `claude plugin uninstall` 這一步」
        // 的說明裡 —— 斷言靠一段**語意相反**的文字通過，等於什麼都沒驗。
        // 代理字串會 drift，指令不會。
        #expect(doc.contains("## Uninstalling"), "英文主文件必須有移除段落")
        #expect(doc.contains("rm ~/.claude/skills/agentaura"),
                "必須寫明真正的移除指令（skills-dir 掛載就是刪那個 symlink）")
        #expect(doc.contains("ln -sfn") && doc.contains("~/.claude/skills/agentaura"),
                "安裝指令也要在文件裡，且與實際機制一致")
        #expect(doc.contains(".agentaura"), "必須說明狀態目錄可安全手動刪除")
    }
}
