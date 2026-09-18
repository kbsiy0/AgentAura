import Testing
import Foundation
@testable import AuraCore
@testable import AuraHookFile

/// 用**真的** aura-hook 二進位 + 真的檔案 + 真的 FSEvents + 真的 pid 探測。
/// 任何一層 mock 都會讓這組測試失去意義。
@Suite("端到端 wired-gate", .serialized)
struct EndToEndWiredGateTests {

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-e2e-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 真的 spawn aura-hook——序列化版本，經過 SpawnGate（T10b），供除了
    /// `fiftyConcurrentSessions` 以外的所有測試共用。
    func fireHook(_ payload: String, root: URL) async throws {
        try await SpawnGate.shared.run {
            try Self.fireHookUnserialized(payload, root: root)
        }
    }

    /// **刻意不經過 SpawnGate**：`fiftyConcurrentSessions` 測的正是「50 個真的併發的 spawn
    /// 會被 pipeline 正確處理」，序列化會讓它不再併發，等於測試失去自己要驗的東西——
    /// 這是本檔唯一的例外，講明原因，不是漏接（`SpawnGateCoverageSourceScanTests` 只要求
    /// 檔案裡看得到 SpawnGate 字樣，不要求每一個呼叫點都走它；上面的 `fireHook` 已經滿足）。
    static func fireHookUnserialized(_ payload: String, root: URL) throws {
        let p = Process()
        p.executableURL = try AuraHookCLITests.binaryURL()
        p.environment = ProcessInfo.processInfo.environment.merging(
            ["AGENTAURA_ROOT": root.path]) { _, new in new }
        let pipe = Pipe()
        p.standardInput = pipe
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        pipe.fileHandleForWriting.write(Data(payload.utf8))
        try pipe.fileHandleForWriting.close()
        p.waitUntilExit()
    }

    struct SpawnResult { let exitCode: Int32; let stdout: String; let stderr: String }

    /// 真的 spawn aura-hook，額外帶 argv（CX8／CX10 用，測 `--agent` 解析）。
    /// 經過 SpawnGate（T10b）序列化。
    static func fireHookWithArgv(_ payload: String, root: URL, argv: [String]) async throws -> SpawnResult {
        try await SpawnGate.shared.run {
            let p = Process()
            p.executableURL = try AuraHookCLITests.binaryURL()
            p.arguments = argv
            p.environment = ProcessInfo.processInfo.environment.merging(
                ["AGENTAURA_ROOT": root.path]) { _, new in new }
            let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
            p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe
            try p.run()
            inPipe.fileHandleForWriting.write(Data(payload.utf8))
            try inPipe.fileHandleForWriting.close()
            let out = outPipe.fileHandleForReading.readDataToEndOfFile()
            let err = errPipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return SpawnResult(exitCode: p.terminationStatus,
                               stdout: String(decoding: out, as: UTF8.self),
                               stderr: String(decoding: err, as: UTF8.self))
        }
    }

    /// 等到 iconState 滿足條件或逾時。
    func wait(for graph: PipelineGraph, until predicate: @escaping (IconState) -> Bool,
              timeout: TimeInterval = 5) async -> IconState {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(graph.iconState) { return graph.iconState }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return graph.iconState
    }

    @Test("hook 觸發 → 檔案 → FSEvents → IconState 變成 waiting")
    func hookToIconState() async throws {
        let root = try makeRoot()
        let graph = PipelineGraph.production(root: root)
        graph.start(); defer { graph.stop() }
        #expect(graph.iconState.activity == .idle)

        try await fireHook(#"{"hook_event_name":"PermissionRequest","session_id":"e2e1","cwd":"/tmp/proj","tool_name":"Bash"}"#, root: root)

        let final = await wait(for: graph) { $0.activity == .waiting }
        #expect(final.activity == .waiting, "整條鏈路必須真的接通")
        #expect(final.attentionCount == 1)
    }

    @Test("三個 session：2 working + 1 error → icon 為 error（D1 端到端）")
    func aggregationEndToEnd() async throws {
        let root = try makeRoot()
        let graph = PipelineGraph.production(root: root)
        graph.start(); defer { graph.stop() }

        // `error` 刻意**先發**，不放在最後。
        //
        // 原本的順序是 working、working、error —— error 剛好是最後一個事件，
        // 所以「last-write-wins」的錯誤實作在這個順序下也會給出 `.error`，
        // 這條端到端測試因此無法單獨排除那個替代假說。
        // 把 error 移到最前面，last-write-wins 會得到 `.working`，測試就有鑑別力了。
        // （同一招在 T09 的 `twoWorkingOneErrorIsError` 用過 —— 固定測資的
        // 元素位置會決定一個 mutation 是否可觀察。）
        try await fireHook(#"{"hook_event_name":"StopFailure","session_id":"e1","reason":"overloaded_error"}"#, root: root)
        try await fireHook(#"{"hook_event_name":"PreToolUse","session_id":"w1","tool_name":"Bash"}"#, root: root)
        try await fireHook(#"{"hook_event_name":"PreToolUse","session_id":"w2","tool_name":"Read"}"#, root: root)

        let final = await wait(for: graph) { $0.activity == .error && $0.counts.values.reduce(0,+) >= 3 }
        #expect(final.activity == .error, "使用者原始舉例，端到端驗證")
        #expect(final.counts[.working] == 2)
        #expect(final.counts[.error] == 1)
    }

    @Test("subagent 在 20ms 內插入事件，waiting 端到端不被抹除（critical bug 的最終防線）")
    func subagentDoesNotMaskWaitingEndToEnd() async throws {
        let root = try makeRoot()
        let graph = PipelineGraph.production(root: root)
        graph.start(); defer { graph.stop() }

        try await fireHook(#"{"hook_event_name":"PermissionRequest","session_id":"mask1","tool_name":"Bash"}"#, root: root)
        _ = await wait(for: graph) { $0.activity == .waiting }

        // 模擬實測時序：主 agent 被擋住時 subagent 連發事件
        for _ in 0..<8 {
            try await fireHook(#"{"hook_event_name":"PostToolUse","session_id":"mask1","tool_name":"Write","agent_id":"sub1","agent_type":"implementer"}"#, root: root)
        }
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(graph.iconState.activity == .waiting,
                "8 個 subagent 事件之後，橘燈仍必須亮著")
    }

    @Test("SessionEnd 之後未確認的 done 仍計入，acknowledgeAll 後才消失")
    func unackedTailEndToEnd() async throws {
        let root = try makeRoot()
        let graph = PipelineGraph.production(root: root)
        graph.start(); defer { graph.stop() }

        try await fireHook(#"{"hook_event_name":"Stop","session_id":"tail1","last_assistant_message":"全部完成"}"#, root: root)
        try await fireHook(#"{"hook_event_name":"SessionEnd","session_id":"tail1","reason":"exit"}"#, root: root)

        // 必須等到 SessionEnd 真的處理完（liveCount 歸零），不能只等 activity == .done：
        // Stop 本身就已經把 activity 設成 .done，但那時 liveness 仍是 .alive
        // （pid 是這個測試行程本身，一直活著）。在高併發下（跑整個 suite 而非只跑
        // 這一條）FSEvents 會把 Stop / SessionEnd 兩次寫入拆成兩個獨立事件，
        // 只等 activity == .done 會在 SessionEnd 事件抵達前提早返回，導致下面的
        // acknowledgeAll 抓不到「已結束」而不會刪檔——實測重現過這個 flake。
        let afterEnd = await wait(for: graph) { $0.activity == .done && $0.liveCount == 0 }
        #expect(afterEnd.activity == .done, "整夜 pipeline 跑完、terminal 收掉，早上仍看得到綠燈")
        #expect(afterEnd.liveCount == 0, "SessionEnd 必須被處理過，session 才算真正結束")

        graph.acknowledgeAll()
        #expect(graph.iconState.activity == .idle)
        #expect(SnapshotIO.allSessionIDs(root: root).isEmpty)
    }

    @Test("50 個 session 併發 hook 全部進到 IconState")
    func fiftyConcurrentSessions() async throws {
        let root = try makeRoot()
        let graph = PipelineGraph.production(root: root)
        graph.start(); defer { graph.stop() }

        DispatchQueue.concurrentPerform(iterations: 50) { i in
            try? Self.fireHookUnserialized(
                #"{"hook_event_name":"PreToolUse","session_id":"c\#(i)","tool_name":"Bash"}"#, root: root)
        }
        let final = await wait(for: graph, until: { $0.counts.values.reduce(0,+) >= 50 }, timeout: 20)
        #expect(final.counts.values.reduce(0, +) >= 50)
    }

    /// CX8：`AgentArgvFixtures` 的 8 格表真的 spawn `aura-hook`，逐格斷言
    /// exit 0、stdout 空、stderr 空——與 CX7（`AgentArgumentTests`，純函式解析）
    /// 共用同一張表，這裡驗的是真正的行程行為，不是解析函式本身。
    @Test("--agent 的 8 格 argv 表，真 spawn 全部靜默（CX8）")
    func auraHookStaysSilentForEveryAgentArgument() async throws {
        let root = try makeRoot()
        #expect(!AgentArgvFixtures.cases.isEmpty, "CX8 的定義域不能空跑")
        for testCase in AgentArgvFixtures.cases {
            let payload = #"{"hook_event_name":"PreToolUse","session_id":"cx8-\#(UUID().uuidString)","tool_name":"Bash"}"#
            let result = try await Self.fireHookWithArgv(payload, root: root, argv: testCase.argv)
            #expect(result.exitCode == 0, "\(testCase.name)：exit code 應為 0，實際 \(result.exitCode)")
            #expect(result.stdout.isEmpty, "\(testCase.name)：stdout 應為空，實際 \(result.stdout.prefix(120))")
            #expect(result.stderr.isEmpty, "\(testCase.name)：stderr 應為空，實際 \(result.stderr.prefix(120))")
        }
    }

    /// CX10：真的用 `--agent codex` spawn `aura-hook`，狀態檔的位元組必須含
    /// `"agent":"codex"`——這是 `main.swift` 有沒有真的把解析出來的 agent 傳進
    /// `MergeRules.merge` 的唯一 wired gate（純函式層的 CX9／CX11／CX12 在
    /// `AgentThreadingTests`，都不 spawn，測不到 `main.swift` 忘了接線這件事）。
    @Test("--agent codex 真 spawn → 狀態檔含 agent:codex（CX10）")
    func codexStateFileCarriesAgent() async throws {
        let root = try makeRoot()
        let sessionID = "cx10-\(UUID().uuidString)"
        let payload = #"{"hook_event_name":"PreToolUse","session_id":"\#(sessionID)","tool_name":"Bash"}"#
        let result = try await Self.fireHookWithArgv(payload, root: root, argv: ["--agent", "codex"])
        #expect(result.exitCode == 0)
        #expect(result.stdout.isEmpty && result.stderr.isEmpty)

        let url = try SnapshotIO.url(for: sessionID, root: root)
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains(#""agent":"codex""#),
                "狀態檔位元組必須含 agent:codex，實際：\(raw)")

        let s = try #require(SnapshotIO.read(sessionID: sessionID, root: root))
        #expect(s.agent == "codex")
    }

    /// CX38（R-8 不變式 2）：同一顆 `aura-hook`，先 Claude payload（round1 fixture，
    /// **無參數**）、再 Codex payload（round4 fixture，`--agent codex`），寫進**同一個**
    /// `AGENTAURA_ROOT`；斷言兩個 snapshot 的 `agent`／activity 各自正確；**反序再跑一次**。
    ///
    /// **「互不覆蓋」是結構性結論，不是被測性質**（r4 m1）：`SnapshotIO` 以
    /// `<session_id>.json` 分檔，兩份 fixture 的 session id 空間本來就不交集
    /// （Claude 的 UUID 與 Codex 的 UUIDv7），所以「兩邊檔案互不覆蓋」在任何實作下
    /// 都會通過（包括完全壞掉的實作）——這裡只在下面斷言一次 `isDisjoint` 當前提檢查，
    /// 不當作這條 gate 的主張。真正有牙齒的是「同一顆二進位服務兩個上游」與
    /// 「兩邊 `agent` 各自正確」，mutation（`--agent` 解析改成一律回 `.claude`）打的
    /// 也是那兩半。**明寫的假設**：兩個上游的 session id 空間不交集，列於 spec §10-16。
    @Test("同一顆 aura-hook 服務 Claude 與 Codex 兩個上游，agent 各自正確（CX38），正序與反序皆驗")
    func oneBinaryServesBothAgentsInOneRoot() async throws {
        let claudeEvents = try Fixtures.rawEvents(named: "round1")
        let codexEvents = try Fixtures.rawEvents(named: "round4-codex")
        #expect(!claudeEvents.isEmpty && !codexEvents.isEmpty, "兩份 fixture 都不能空跑")

        try await runDualAgentSequence(claudeFirst: true, claudeEvents: claudeEvents, codexEvents: codexEvents)
        try await runDualAgentSequence(claudeFirst: false, claudeEvents: claudeEvents, codexEvents: codexEvents)
    }

    func runDualAgentSequence(claudeFirst: Bool, claudeEvents: [[String: Any]],
                              codexEvents: [[String: Any]]) async throws {
        let root = try makeRoot()

        func fireClaude() async throws {
            for dict in claudeEvents {
                try await fireHook(String(decoding: try Fixtures.jsonData(dict), as: UTF8.self), root: root)
            }
        }
        func fireCodex() async throws {
            for dict in codexEvents {
                _ = try await Self.fireHookWithArgv(String(decoding: try Fixtures.jsonData(dict), as: UTF8.self),
                                                    root: root, argv: ["--agent", "codex"])
            }
        }

        if claudeFirst { try await fireClaude(); try await fireCodex() }
        else { try await fireCodex(); try await fireClaude() }

        let claudeSessionIDs = Set(claudeEvents.compactMap { $0["session_id"] as? String })
        let codexSessionIDs = Set(codexEvents.compactMap { $0["session_id"] as? String })
        #expect(claudeSessionIDs.isDisjoint(with: codexSessionIDs),
                "明寫的假設：兩個上游的 session id 空間不交集（spec §10-16），不是這條 gate 的主張")

        // Codex 側：round4 的 4 個 session 全部以 Stop → SessionEnd 收尾（實測 fixture
        // 序列），agent 必須各自標成 codex。
        for id in codexSessionIDs {
            let s = try #require(SnapshotIO.read(sessionID: id, root: root), "Codex session \(id) 沒有落檔")
            #expect(s.agent == "codex", "Codex session \(id) 的 agent 欄位必須是 codex")
            #expect(s.mainActivity == .done, "round4 的每個 session 最後一筆活動事件都是 Stop")
        }
        // Claude 側：round1 的兩個 session，agent 必須不存在（CX9 同一個機制）；
        // 91a40169… 收尾在 Stop（done），e69dc6d9… 最後一筆是 PreToolUse（working）——
        // 兩種收尾都各驗一次，順便確認 activity 真的走對規則，不是巧合地都是同一值。
        let claudeDone = try #require(
            SnapshotIO.read(sessionID: "91a40169-42ef-4026-b902-2057a7002665", root: root))
        #expect(claudeDone.agent == nil)
        #expect(claudeDone.mainActivity == .done)

        let claudeWorking = try #require(
            SnapshotIO.read(sessionID: "e69dc6d9-7364-4619-a438-159b48151b02", root: root))
        #expect(claudeWorking.agent == nil)
        #expect(claudeWorking.mainActivity == .working)
    }
}
