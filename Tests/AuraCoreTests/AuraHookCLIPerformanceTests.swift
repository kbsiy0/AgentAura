import Testing
import Foundation
@testable import AuraCore

/// `aura-hook` 的效能閘門。
///
/// **從 `AuraHookCLITests` 拆出來**：那個檔撞到 300 行上限，而這個專案的規約說
/// 超標通常代表一個檔在做兩件事——「黑箱行為（永遠 exit 0、輸出為空、畸形輸入不炸）」
/// 與「跑得夠快」確實是兩件事，受測面也不同。拆檔是照著那條規則走，不是為了讓數字過關。
@Suite("aura-hook 效能（相對比值）", .serialized)
struct AuraHookCLIPerformanceTests {

    /// 與 `AuraHookCLITests` 共用同一組 spawn 慣例：一律經 `SpawnGate`，一律注入
    /// `AGENTAURA_ROOT` 到拋棄式目錄。
    func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aura-perf-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func binaryURL() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        while dir.pathComponents.count > 1 {
            dir = dir.deletingLastPathComponent()
            let candidate = dir.appendingPathComponent("plugin/bin/aura-hook")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        throw PerfFailure("找不到 plugin/bin/aura-hook —— 先跑 ./scripts/build-plugin.sh")
    }

    struct PerfFailure: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = d }
    }

    func runHook(_ payload: String, root: URL) async throws {
        try await SpawnGate.shared.run {
            let p = Process()
            p.executableURL = try Self.binaryURL()
            p.environment = ProcessInfo.processInfo.environment.merging(
                ["AGENTAURA_ROOT": root.path]) { _, new in new }
            let inPipe = Pipe()
            p.standardInput = inPipe
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            inPipe.fileHandleForWriting.write(Data(payload.utf8))
            try? inPipe.fileHandleForWriting.close()
            p.waitUntilExit()
        }
    }

    /// 相對比值，不是絕對毫秒（CLAUDE.md gate 哲學第 6 條）。「中位數 < 50ms」被負載
    /// 打穿過三次，最近是 2026-09-17 的 CI（199.8ms）。兩邊都經過 `SpawnGate`——
    /// 控制組若不排隊，排隊時間只會灌進分子。
    @Test("單次呼叫的成本相對於純 spawn 的比值（不量絕對毫秒）")
    func latency() async throws {
        let root = try makeRoot()
        var aura: [Double] = [], ctrl: [Double] = []
        for i in 0..<20 {
            let t = Date()
            try await runHook(#"{"hook_event_name":"PreToolUse","session_id":"perf\#(i % 3)","tool_name":"Bash"}"#, root: root)
            aura.append(Date().timeIntervalSince(t) * 1000)
            let c = Date()
            try await SpawnGate.shared.run {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/true")
                try task.run(); task.waitUntilExit()
            }
            ctrl.append(Date().timeIntervalSince(c) * 1000)
        }
        let a = aura.sorted()[aura.count / 2], c = ctrl.sorted()[ctrl.count / 2]
        try #require(c > 0, "控制組量到 0ms —— 量測本身壞了，比值不可信")
        #expect(a / c <= 6, """
            aura-hook \(a)ms vs 空行程 \(c)ms＝\(a / c)×，超過 6× 上限。機器變慢會讓
            兩邊一起慢、比值不變，所以這代表它真的多做了工作。
            """)
    }
}
