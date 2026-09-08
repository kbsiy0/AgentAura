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

    /// 真的 spawn aura-hook。
    func fireHook(_ payload: String, root: URL) throws {
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

        try fireHook(#"{"hook_event_name":"PermissionRequest","session_id":"e2e1","cwd":"/tmp/proj","tool_name":"Bash"}"#, root: root)

        let final = await wait(for: graph) { $0.activity == .waiting }
        #expect(final.activity == .waiting, "整條鏈路必須真的接通")
        #expect(final.attentionCount == 1)
    }

    @Test("三個 session：2 working + 1 error → icon 為 error（D1 端到端）")
    func aggregationEndToEnd() async throws {
        let root = try makeRoot()
        let graph = PipelineGraph.production(root: root)
        graph.start(); defer { graph.stop() }

        try fireHook(#"{"hook_event_name":"PreToolUse","session_id":"w1","tool_name":"Bash"}"#, root: root)
        try fireHook(#"{"hook_event_name":"PreToolUse","session_id":"w2","tool_name":"Read"}"#, root: root)
        try fireHook(#"{"hook_event_name":"StopFailure","session_id":"e1","reason":"overloaded_error"}"#, root: root)

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

        try fireHook(#"{"hook_event_name":"PermissionRequest","session_id":"mask1","tool_name":"Bash"}"#, root: root)
        _ = await wait(for: graph) { $0.activity == .waiting }

        // 模擬實測時序：主 agent 被擋住時 subagent 連發事件
        for _ in 0..<8 {
            try fireHook(#"{"hook_event_name":"PostToolUse","session_id":"mask1","tool_name":"Write","agent_id":"sub1","agent_type":"implementer"}"#, root: root)
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

        try fireHook(#"{"hook_event_name":"Stop","session_id":"tail1","last_assistant_message":"全部完成"}"#, root: root)
        try fireHook(#"{"hook_event_name":"SessionEnd","session_id":"tail1","reason":"exit"}"#, root: root)

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
            try? self.fireHook(
                #"{"hook_event_name":"PreToolUse","session_id":"c\#(i)","tool_name":"Bash"}"#, root: root)
        }
        let final = await wait(for: graph, until: { $0.counts.values.reduce(0,+) >= 50 }, timeout: 20)
        #expect(final.counts.values.reduce(0, +) >= 50)
    }
}
