import Testing
import Foundation
@testable import AuraCore
@testable import AuraHookFile

@Suite("Plugin 設定 wired-gate")
struct PluginWiringTests {

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

    static func hooksFile() throws -> [String: Any] {
        let url = repoRoot().appendingPathComponent("plugin/hooks/hooks.json")
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// 事件對照表在**內層**的 `"hooks"` 物件裡。
    ///
    /// 這個 `["hooks"]` 是被 `claude plugin validate` 教出來的：先前的版本把事件
    /// 直接放在最外層，validator 回報
    /// 「PreToolUse/... is declared at the top level, outside the "hooks" object」——
    /// 整個 plugin 的 hook 一個都不會載入，而本檔案的每一條測試當時**全綠**，
    /// 因為它們比對的是自己讀出來的那份字典，不是平台的契約。
    static func hooksJSON() throws -> [String: Any] {
        try #require(try hooksFile()["hooks"] as? [String: Any],
                     "hooks.json 的事件必須包在最外層的 \"hooks\" 物件裡")
    }

    /// 攤平出 hooks.json 裡的每一個 hook entry。
    static func entries() throws -> [(event: String, entry: [String: Any])] {
        var out: [(String, [String: Any])] = []
        for (event, value) in try hooksJSON() {
            for matcher in (value as? [[String: Any]]) ?? [] {
                for h in (matcher["hooks"] as? [[String: Any]]) ?? [] { out.append((event, h)) }
            }
        }
        return out
    }

    @Test("plugin.json 是合法 JSON 且有 name")
    func manifestValid() throws {
        let url = Self.repoRoot().appendingPathComponent("plugin/.claude-plugin/plugin.json")
        let obj = try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        #expect(obj?["name"] as? String == "agentaura")
    }

    @Test("每一個 hook 都是 async: true —— 絕不可拖慢 agent")
    func allHooksAreAsync() throws {
        let all = try Self.entries()
        #expect(!all.isEmpty)
        for (event, h) in all {
            #expect(h["async"] as? Bool == true, "\(event) 的 hook 缺少 async: true")
        }
    }

    @Test("每一個 hook 的 command 都指向同一個 aura-hook 相對路徑")
    func allHooksPointAtAuraHook() throws {
        let all = try Self.entries()
        #expect(!all.isEmpty)
        for (event, h) in all {
            let cmd = try #require(h["command"] as? String)
            // 官方 plugin 的慣例是把路徑加引號 —— $HOME 含空白時才不會裂開。
            #expect(cmd == "\"${CLAUDE_PLUGIN_ROOT}/bin/aura-hook\"",
                    "\(event) 的 command 不一致：\(cmd)")
        }
    }

    /// **source-derived 跨層一致性 gate。**
    ///
    /// 來源集合從 `EventMapping.handledEvents`（生產碼）推導，不是手維護的第二份清單。
    /// user CLAUDE.md Lessons Learned #9：hand-maintained 清單自己會 drift ——
    /// 本專案已實際發生過：`Elicitation` 映射到 `waiting` 卻沒註冊，那個「MCP server
    /// 在等你輸入」的狀態永遠收不到，而單元測試照樣全綠。
    ///
    /// 斷言是**雙向等式**，兩個方向都有代價：
    /// - 有映射沒註冊 → 對照表是死碼，該狀態永遠收不到（tested≠wired）
    /// - 有註冊沒映射 → 每個事件白付一次 hook 呼叫，卻不影響任何狀態
    @Test("hooks.json 註冊的 event 集合必須等於 EventMapping.handledEvents")
    func registeredEventsMatchHandledEvents() throws {
        let registered = Set(try Self.hooksJSON().keys)
        let handled = EventMapping.handledEvents

        let mappedNotRegistered = handled.subtracting(registered)
        let registeredNotMapped = registered.subtracting(handled)

        #expect(mappedNotRegistered.isEmpty,
                "有映射卻沒註冊（對照表是死碼）：\(mappedNotRegistered.sorted())")
        #expect(registeredNotMapped.isEmpty,
                "有註冊卻沒映射（白付 hook 呼叫）：\(registeredNotMapped.sorted())")
    }

    /// source-derived 雙向等式，與 `registeredEventsMatchHandledEvents` 同一個理由。
    ///
    /// - matcher 少收 → 該型別的 `Notification` 永遠不會抵達，對照表是死碼
    /// - matcher 多收 → 收了卻被當雜訊，白付 hook 呼叫
    @Test("Notification matcher 必須等於 EventMapping.notificationMatcherTypes")
    func notificationMatcherMatchesMapping() throws {
        let notif = try #require(try Self.hooksJSON()["Notification"] as? [[String: Any]])
        let matcher = try #require(notif.first?["matcher"] as? String)
        let inMatcher = Set(matcher.split(separator: "|").map(String.init))
        let expected = EventMapping.notificationMatcherTypes

        #expect(expected.subtracting(inMatcher).isEmpty,
                "matcher 漏收（對照表是死碼）：\(expected.subtracting(inMatcher).sorted())")
        #expect(inMatcher.subtracting(expected).isEmpty,
                "matcher 多收（白付 hook 呼叫）：\(inMatcher.subtracting(expected).sorted())")

        // 再確認 matcher 收的每一個型別實際上真的會改變狀態
        for t in inMatcher {
            #expect(EventMapping.effect(forEvent: "Notification", notificationType: t) != .noChange,
                    "matcher 收了 \(t) 但對照表把它當雜訊")
        }
    }

    /// **結構 gate。** 事件不得出現在最外層。
    @Test("hooks.json 的事件包在 \"hooks\" 物件裡，最外層沒有裸事件名")
    func hooksAreNestedUnderHooksKey() throws {
        let file = try Self.hooksFile()
        #expect(file["hooks"] != nil, "缺少最外層的 \"hooks\" 物件")
        let leaked = EventMapping.handledEvents.filter { file[$0] != nil }
        #expect(leaked.isEmpty, """
            這些事件被放在最外層，plugin 的 hook 一個都不會載入：\(leaked.sorted())
            `claude plugin validate` 會說 "declared at the top level, outside the \"hooks\" object"。
            """)
    }

    /// **平台契約 gate —— 用官方 validator，不用手寫的假設。**
    ///
    /// 手寫的檢查只能驗我以為的契約；`claude plugin validate` 驗的是平台真正的契約。
    /// 這個 gate 抓到過兩個手寫檢查完全看不見的錯：`author` 必須是物件而非字串，
    /// 以及事件必須包在 `"hooks"` 物件裡（否則整個 plugin 的 hook 都不載入）。
    ///
    /// **必須要求零 warning**，不能只看 exit code：validator 對
    /// 「unknown hook event」、「no type」、「async 型別錯」都只給 **warning**
    /// 並仍然 `exit 0`，而每一個 warning 都寫著 **entry ignored at runtime** ——
    /// 也就是一個靜默的死 hook。實測確認 exit code 在有 warning 時仍是 0。
    @Test("claude plugin validate 對 plugin 與 marketplace 都零錯誤零警告")
    func officialValidatorIsClean() throws {
        for target in ["plugin", "."] {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = ["claude", "plugin", "validate", target]
            task.currentDirectoryURL = Self.repoRoot()
            let pipe = Pipe()
            task.standardOutput = pipe; task.standardError = pipe
            try task.run()
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            task.waitUntilExit()

            #expect(task.terminationStatus == 0, "validate \(target) 失敗：\(out)")
            #expect(!out.contains("warning"), """
                validate \(target) 有 warning —— 每個 warning 都代表一個
                「entry ignored at runtime」的死 hook：
                \(out)
                """)
            #expect(out.contains("Validation passed"), "validate \(target) 沒有印出通過：\(out)")
        }
    }

    @Test("aura-hook 二進位存在且可執行（安裝腳本的驗收條件）")
    func auraHookBinaryExists() throws {
        let root = Self.repoRoot()
        let candidates = ["\(".build/debug")/aura-hook", "\(".build/release")/aura-hook"]
            .map { root.appendingPathComponent($0) }
        #expect(candidates.contains { FileManager.default.isExecutableFile(atPath: $0.path) },
                "先跑 swift build。安裝腳本必須把此二進位放到 plugin/bin/aura-hook")
    }
}

@Suite("PipelineGraph composition root", .serialized)
struct CompositionRootTests {

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-graph-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("production() 的每個依賴都真的接上，沒有 nil")
    func productionGraphIsWired() {
        let g = PipelineGraph.production(root: try! makeRoot())
        #expect(g.source is HookFileSource, "production 必須用真的檔案來源")
        #expect(g.liveness is SysctlLiveness, "production 必須用真的 pid 探測，不是 stub")
        #expect(g.policy is PriorityAggregatePolicy)
    }

    @Test("start() 會消耗 bootstrap 的結果並更新 iconState")
    func startConsumesBootstrap() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "boot1", root: root) { _ in
            var s = SessionSnapshot(sessionID: "boot1")
            s.mainActivity = .error; s.terminated = true; s.writtenAt = Date()
            return s
        }
        let g = PipelineGraph.production(root: root)
        g.start()
        defer { g.stop() }
        #expect(g.iconState.activity == .error,
                "app 沒開時累積的未確認 error，啟動後必須立刻反映在 icon 上")
    }

    @Test("onIconStateChange callback 真的被呼叫（spy 斷言，不接受被 catch-all 吞掉）")
    func callbackIsInvoked() throws {
        let root = try makeRoot()
        let g = PipelineGraph.production(root: root)
        var received: [IconState] = []
        g.onIconStateChange = { received.append($0) }

        try SnapshotIO.update(sessionID: "cb1", root: root) { _ in
            var s = SessionSnapshot(sessionID: "cb1"); s.mainActivity = .waiting
            s.pid = getpid(); s.pidStartedAt = SysctlLiveness().startTime(ofPID: getpid())
            s.writtenAt = Date(); return s
        }
        g.start()
        defer { g.stop() }
        #expect(!received.isEmpty, "start() 必須觸發至少一次 icon 更新")
        #expect(received.last?.activity == .waiting)
    }

    @Test("acknowledgeAll 會刪除已結束且已確認的狀態檔")
    func acknowledgeDeletesFiles() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "ack1", root: root) { _ in
            var s = SessionSnapshot(sessionID: "ack1")
            s.mainActivity = .done; s.terminated = true; s.writtenAt = Date(); return s
        }
        let g = PipelineGraph.production(root: root)
        g.start(); defer { g.stop() }
        #expect(g.iconState.activity == .done)

        g.acknowledgeAll()
        #expect(g.iconState.activity == .idle, "確認後尾巴清空，燈回正常")
        #expect(SnapshotIO.allSessionIDs(root: root).isEmpty, "已結束且已確認 → 檔案刪除")
    }

    @Test("狀態檔被外部刪除後，refreshLiveness 移除該 session")
    func refreshLivenessDropsDeletedFiles() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "gone1", root: root) { _ in
            var s = SessionSnapshot(sessionID: "gone1")
            s.mainActivity = .waiting
            s.pid = getpid(); s.pidStartedAt = SysctlLiveness().startTime(ofPID: getpid())
            s.writtenAt = Date(); return s
        }
        let g = PipelineGraph.production(root: root)
        g.start(); defer { g.stop() }
        #expect(g.iconState.activity == .waiting)

        // 模擬使用者手動清理：rm ~/.agentaura/sessions/*
        try SnapshotIO.delete(sessionID: "gone1", root: root)
        g.refreshLiveness()
        #expect(g.iconState.activity == .idle, "檔案消失 → 不得留下幽靈 session")
    }

    @Test("狀態目錄被整個刪除後，refreshLiveness 重建它")
    func refreshLivenessRecreatesRoot() throws {
        let root = try makeRoot()
        let g = PipelineGraph.production(root: root)
        g.start(); defer { g.stop() }
        try FileManager.default.removeItem(at: root)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        g.refreshLiveness()
        #expect(FileManager.default.fileExists(atPath: root.path),
                "目錄不存在會讓後續 hook 寫入失敗（aura-hook 會靜默放棄）")
    }

    @Test("refreshLiveness 會把 pid 已死的 working session 移出")
    func refreshLivenessDropsDeadSessions() throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "dead1", root: root) { _ in
            var s = SessionSnapshot(sessionID: "dead1")
            s.mainActivity = .working
            s.pid = 999_999; s.pidStartedAt = 12_345      // 不存在的 pid
            s.writtenAt = Date(); return s
        }
        let g = PipelineGraph.production(root: root)
        g.start(); defer { g.stop() }
        g.refreshLiveness()
        #expect(g.iconState.activity == .idle,
                "terminal 被強制關掉、SessionEnd 沒來 → 不得永遠卡 working")
    }
}
