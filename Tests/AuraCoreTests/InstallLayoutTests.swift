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
    func pluginBinaryWorks() throws {
        let bin = try Self.expectedBinaryPath()
        try #require(FileManager.default.isExecutableFile(atPath: bin.path))
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-install-\(UUID().uuidString)/sessions")

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

        #expect(p.terminationStatus == 0)
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("inst1.json").path),
            "安裝用的二進位必須真的能寫狀態檔，不只是存在")
    }

    @Test("INSTALL.md 存在且含移除步驟（R6：一步安裝、一步移除）")
    func installDocHasUninstall() throws {
        let doc = try String(contentsOf: Self.repoRoot().appendingPathComponent("docs/INSTALL.md"),
                             encoding: .utf8)
        #expect(doc.contains("plugin uninstall"), "必須寫明如何完整移除")
        #expect(doc.contains(".agentaura"), "必須說明狀態目錄可安全手動刪除")
    }
}
