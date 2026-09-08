// Tests/AuraCoreTests/AuraHookCLITests.swift
import Testing
import Foundation
@testable import AuraCore
@testable import AuraHookFile

@Suite("aura-hook CLI 黑箱行為")
struct AuraHookCLITests {

    /// 找出 `swift build` 產出的 aura-hook。
    static func binaryURL() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        while dir.pathComponents.count > 1 {
            dir = dir.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                break
            }
        }
        for config in ["debug", "release"] {
            let url = dir.appendingPathComponent(".build/\(config)/aura-hook")
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        throw TestError.binaryMissing
    }

    enum TestError: Error { case binaryMissing }

    struct Result { let exitCode: Int32; let stdout: String; let stderr: String }

    /// 把 payload 餵進 stdin，回傳 exit code 與輸出。
    func run(_ payload: String, root: URL) throws -> Result {
        let p = Process()
        p.executableURL = try Self.binaryURL()
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
        return Result(exitCode: p.terminationStatus,
                      stdout: String(decoding: out, as: UTF8.self),
                      stderr: String(decoding: err, as: UTF8.self))
    }

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-cli-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // ---- 正常路徑 ----

    @Test("寫入狀態檔並 exit 0")
    func happyPath() throws {
        let root = try makeRoot()
        let r = try run(#"{"hook_event_name":"PermissionRequest","session_id":"cli1","cwd":"/tmp","tool_name":"Bash"}"#, root: root)
        #expect(r.exitCode == 0)
        let s = try #require(SnapshotIO.read(sessionID: "cli1", root: root))
        #expect(s.mainActivity == .waiting)
        #expect(s.mainTool == "Bash")
        #expect(s.schema == 1)
    }

    @Test("記錄 pid 與 pid_started_at，且該 pid 當下可驗證為活著")
    func recordsPIDAndStartTime() throws {
        let root = try makeRoot()
        _ = try run(#"{"hook_event_name":"PreToolUse","session_id":"cli2"}"#, root: root)
        let s = try #require(SnapshotIO.read(sessionID: "cli2", root: root))
        let pid = try #require(s.pid)
        let started = try #require(s.pidStartedAt)
        #expect(pid > 0)
        #expect(started > 1_600_000_000)
        // 父行程就是這個測試行程 —— 應仍活著
        #expect(SysctlLiveness().isAlive(pid: pid, startedAt: started))
    }

    @Test("端到端：主槽 waiting 時 subagent 事件不得改變 activity")
    func subagentDoesNotMaskWaitingEndToEnd() throws {
        let root = try makeRoot()
        _ = try run(#"{"hook_event_name":"PermissionRequest","session_id":"cli3","tool_name":"Bash"}"#, root: root)
        _ = try run(#"{"hook_event_name":"PostToolUse","session_id":"cli3","tool_name":"Write","agent_id":"a1","agent_type":"Explore"}"#, root: root)
        let s = try #require(SnapshotIO.read(sessionID: "cli3", root: root))
        #expect(s.mainActivity == .waiting, "端到端也必須保住 waiting")
        #expect(s.subActivity == nil, "主槽靜止 → 忽略 subagent（§2.5.1）")
        #expect(s.effectiveActivity == .waiting)
    }

    @Test("端到端：主槽 working 時 subagent 事件寫進 sub 槽")
    func subagentGoesToSubSlotWhenWorking() throws {
        let root = try makeRoot()
        _ = try run(#"{"hook_event_name":"PreToolUse","session_id":"cli3b","tool_name":"Bash"}"#, root: root)
        _ = try run(#"{"hook_event_name":"PostToolUse","session_id":"cli3b","tool_name":"Grep","agent_id":"a1","agent_type":"Explore"}"#, root: root)
        let s = try #require(SnapshotIO.read(sessionID: "cli3b", root: root))
        #expect(s.mainActivity == .working)
        #expect(s.subActivity == .working)
        #expect(s.subTool == "Grep")
        #expect(s.subAgentType == "Explore")
    }

    @Test("累積欄位跨多次呼叫保留")
    func accumulatesAcrossInvocations() throws {
        let root = try makeRoot()
        _ = try run(#"{"hook_event_name":"UserPromptSubmit","session_id":"cli4"}"#, root: root)
        for _ in 0..<3 {
            _ = try run(#"{"hook_event_name":"PostToolUseFailure","session_id":"cli4","tool_name":"Bash"}"#, root: root)
        }
        _ = try run(#"{"hook_event_name":"SubagentStart","session_id":"cli4","agent_id":"a1","agent_type":"Explore"}"#, root: root)
        let s = try #require(SnapshotIO.read(sessionID: "cli4", root: root))
        #expect(s.toolFailures == 3)
        #expect(s.subagents == ["Explore": 1])
        #expect(s.turnStartedAt != nil)
    }

    @Test("真實 fixture 全部餵進去都 exit 0 且產生狀態檔")
    func allRealPayloadsAccepted() throws {
        let root = try makeRoot()
        for json in try Fixtures.rawEvents(named: "round1") {
            let data = try Fixtures.jsonData(json)
            let r = try run(String(decoding: data, as: UTF8.self), root: root)
            #expect(r.exitCode == 0)
        }
        #expect(!SnapshotIO.allSessionIDs(root: root).isEmpty)
    }

    // ---- 靜默失敗（Global Constraint）----

    @Test("畸形輸入一律 exit 0 且無任何輸出", arguments: [
        "", "   ", "not json", "{", "}{", "null", "[]", "[1,2,3]", "\"str\"", "42",
        #"{"session_id":"x"}"#,                        // 缺 hook_event_name
        #"{"hook_event_name":"Stop"}"#,                 // 缺 session_id
        #"{"hook_event_name":"Stop","session_id":123}"#,// session_id 型別錯
    ])
    func malformedInputIsSilent(_ payload: String) throws {
        let r = try run(payload, root: try makeRoot())
        #expect(r.exitCode == 0, "觀測性絕不可干擾 agent")
        #expect(r.stdout.isEmpty, "不得有任何 stdout")
        #expect(r.stderr.isEmpty, "不得有任何 stderr")
    }

    @Test("session_id 含 path traversal 時不寫任何檔案且 exit 0")
    func pathTraversalRejected() throws {
        let root = try makeRoot()
        let outside = root.deletingLastPathComponent().appendingPathComponent("escaped.json")
        let r = try run(#"{"hook_event_name":"Stop","session_id":"../escaped"}"#, root: root)
        #expect(r.exitCode == 0)
        #expect(!FileManager.default.fileExists(atPath: outside.path), "不得寫到目錄外")
        #expect(SnapshotIO.allSessionIDs(root: root).isEmpty)
    }

    @Test("目錄唯讀時仍 exit 0（磁碟滿 / 權限問題的代理情境）")
    func readOnlyRootIsSilent() throws {
        let root = try makeRoot()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }
        let r = try run(#"{"hook_event_name":"Stop","session_id":"ro1"}"#, root: root)
        #expect(r.exitCode == 0)
        #expect(r.stdout.isEmpty, "有 stdout：\(r.stdout.prefix(120))")
        #expect(r.stderr.isEmpty, "有 stderr：\(r.stderr.prefix(120))")
    }

    @Test("stdin 直接關閉（沒有任何輸入）仍 exit 0")
    func closedStdin() throws {
        let root = try makeRoot()
        let p = Process()
        p.executableURL = try Self.binaryURL()
        p.environment = ProcessInfo.processInfo.environment.merging(
            ["AGENTAURA_ROOT": root.path]) { _, new in new }
        let inPipe = Pipe(), out = Pipe(), err = Pipe()
        p.standardInput = inPipe; p.standardOutput = out; p.standardError = err
        try p.run()
        try inPipe.fileHandleForWriting.close()   // 立刻關閉，不寫任何 bytes
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0)
        #expect(o.isEmpty && e.isEmpty)
    }

    /// **行為式強制「任何錯誤都靜默 exit 0」**，取代靠人讀程式碼確認沒有
    /// force unwrap / `try!` / `fatalError`。
    ///
    /// 用 regex 掃原始碼找 `!` 的誤報率太高（`!=`、`!x`、字串裡的 `!` 都會中）。
    /// 改成把真實 payload 系統性破壞後餵進去 —— Swift runtime trap 會以 signal
    /// 中止（terminationStatus 非 0），所以行為測試抓得到，而且不依賴我對程式碼的閱讀。
    @Test("真實 payload 的系統性破壞版本全部 exit 0 且無輸出")
    func fuzzedRealPayloadsAreSilent() throws {
        let root = try makeRoot()
        let reals = try Fixtures.rawEvents(named: "round2")
        var cases: [(String, Data)] = []

        // **分層取樣**，不是對時間序列做 modulo。
        //
        // 前一版寫 `where i % 4 == 0`，實測讓四種事件
        //（`SessionStart`、`UserPromptSubmit`、`PostToolUseFailure`、`Notification`）
        // 與七個欄位（`message`、`model`、`error`、`source`、`notification_type`、
        // `prompt`、`is_interrupt`）**完全不入選** —— 稀有事件在時間序列上分布不均，
        // modulo 會系統性地漏掉它們。其中 `PostToolUseFailure.error` 在本專案
        // 先前真的出過 bug（見 commit 7ab82bc）。
        //
        // 改成：每一種 event、每一個新出現的欄位都保證至少入選一筆，
        // 其餘同類事件再用 modulo 縮減數量。下面兩條 source-derived 斷言
        // 會在覆蓋被掏空時指名漏掉的是什麼。
        var seenEvent: Set<String> = []
        var seenKey: Set<String> = []
        var picked: [(Int, [String: Any])] = []
        for (i, json) in reals.enumerated() {
            let isNewEvent = seenEvent.insert((json["hook_event_name"] as? String) ?? "?").inserted
            let isNewKey = !Set(json.keys).subtracting(seenKey).isEmpty
            if isNewEvent || isNewKey || i % 4 == 0 {
                seenKey.formUnion(json.keys)
                picked.append((i, json))
            }
        }
        let allEvents = Set(reals.compactMap { $0["hook_event_name"] as? String })
        #expect(seenEvent.subtracting(["?"]) == allEvents,
                "漏掉的 event：\(allEvents.subtracting(seenEvent).sorted())")
        let allKeys = Set(reals.flatMap { $0.keys })
        #expect(seenKey == allKeys, "漏掉的欄位：\(allKeys.subtracting(seenKey).sorted())")

        for (i, json) in picked {
            let full = try Fixtures.jsonData(json)

            // (1) 在多個比例處截斷
            for frac in [0.1, 0.35, 0.6, 0.9] {
                cases.append(("truncate-\(frac)-\(i)", full.prefix(Int(Double(full.count) * frac))))
            }
            // (2) 逐一移除每個 key
            for key in json.keys {
                var m = json; m.removeValue(forKey: key)
                cases.append(("drop-\(key)-\(i)", try Fixtures.jsonData(m)))
            }
            // (3) 逐一把每個值換成型別不符的東西
            for key in json.keys {
                for wrong: Any in [NSNull(), 42, ["nested": ["deep": [1, 2, 3]]], [1, 2, 3]] {
                    var m = json; m[key] = wrong
                    cases.append(("retype-\(key)-\(i)", try Fixtures.jsonData(m)))
                }
            }
        }

        #expect(cases.count > 200, "破壞案例數應有規模，實際 \(cases.count)")

        for (label, data) in cases {
            let r = try run(String(decoding: data, as: UTF8.self), root: root)
            #expect(r.exitCode == 0, "\(label) 的 exit code 是 \(r.exitCode)，不是 0")
            #expect(r.stdout.isEmpty, "\(label) 有 stdout：\(r.stdout.prefix(120))")
            #expect(r.stderr.isEmpty, "\(label) 有 stderr：\(r.stderr.prefix(120))")
        }

        // 破壞過程不得在狀態目錄產生非預期檔案
        let files = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for f in files {
            #expect(f.hasSuffix(".json"), "狀態目錄出現非 .json 檔：\(f)")
            #expect(SnapshotIO.isSafeSessionID(String(f.dropLast(5))),
                    "狀態目錄出現不安全的檔名：\(f)")
        }
    }

    @Test("超大 payload（1MB last_assistant_message）不 crash 且 exit 0")
    func hugePayload() throws {
        let big = String(repeating: "長訊息內容 ", count: 100_000)
        let json = try String(decoding: JSONSerialization.data(withJSONObject: [
            "hook_event_name": "Stop", "session_id": "big1", "last_assistant_message": big,
        ]), as: UTF8.self)
        let r = try run(json, root: try makeRoot())
        #expect(r.exitCode == 0)
    }

    // ---- 效能（DoD：p95 < 5ms）----

    @Test("單次呼叫的 wall-clock 中位數 < 50ms（含 process spawn）")
    func latency() throws {
        let root = try makeRoot()
        var times: [Double] = []
        for i in 0..<20 {
            let t = Date()
            _ = try run(#"{"hook_event_name":"PreToolUse","session_id":"perf\#(i % 3)","tool_name":"Bash"}"#, root: root)
            times.append(Date().timeIntervalSince(t) * 1000)
        }
        let median = times.sorted()[times.count / 2]
        #expect(median < 50, "中位數 \(median)ms —— 含 spawn 的寬鬆門檻；精確 p95 用 hyperfine 量（Task 13）")
    }
}
