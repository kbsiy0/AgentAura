import Testing
import Foundation
@testable import AuraCore
@testable import AuraHookFile

/// codex-support T01 骨架（CX13，**T05 解除**）：`round4-codex.ndjson` 的 18 筆逐筆解析，
/// 期望值來自 `docs/2026-09-18-codex-hook-probe.md` 的「每種事件的欄位」表（F2，該文件
/// 第 36–45 行），**不是從 `HookPayload`／`EventMapping` 現有行為反推**——round4 的
/// 6 種事件全部是既有 `handledEvents` 的既有映射（D-e：Codex 只在 `Interrupt` 上加新
/// 東西），所以下面 `probeTable` 的期望值就是 `Sources/AuraCore/EventMapping.swift`
/// 今天已經寫死的那六條規則本身，是讀原始碼寫下來的，不是呼叫它再拿結果比對自己。
///
/// **型別依賴（RED 理由＝編譯依賴，不是斷言失敗）**：`MergeRules.merge(...)` 要到 T05
/// 才加上不給預設值的 `agent:` 參數（spec §4.1「5a」），下面的真斷言用的是**新**簽章。
/// 在那之前，真斷言關在 `#if AURA_CODEX_PENDING_T05` 區塊裡（Swift 對不啟用的 `#if`
/// 分支不做型別檢查，所以引用尚不存在的簽章不會讓整個 test target 編不過）；
/// `#else` 分支用 `Issue.record` 頂著，讓這條測試此刻確實是 RED。
///
/// **T05 解除方式**：把本檔測試函式裡的 `#if AURA_CODEX_PENDING_T05` / `#else` 到
/// `Issue.record(...)` / `#endif` 這三行拿掉，只留中間原本在 `#if` 分支裡的真斷言。
@Suite("round4-codex.ndjson 覆蓋（CX13）")
struct Round4FixtureTests {

    struct ProbeRow { let event: String; let expectedEffect: EventEffect }

    static let probeTable: [ProbeRow] = [
        ProbeRow(event: "SessionStart", expectedEffect: .setActivity(.idle)),
        ProbeRow(event: "UserPromptSubmit", expectedEffect: .setActivity(.working)),
        ProbeRow(event: "PreToolUse", expectedEffect: .setActivity(.working)),
        ProbeRow(event: "PostToolUse", expectedEffect: .setActivity(.working)),
        ProbeRow(event: "Stop", expectedEffect: .setActivity(.done)),
        ProbeRow(event: "SessionEnd", expectedEffect: .sessionEnded),
    ]

    /// 讀 `round4-codex.ndjson`，把每行的 `_payload` 子物件重新序列化成獨立的
    /// `Data`——fixture 的外層 `{"_t":...,"_payload":{...}}` 是探針腳本自己的記錄格式，
    /// 不是真的 hook payload 形狀（同 `FixtureCodeAnchorTests.scanFixtures` 的處理方式）。
    static func loadPayloads() throws -> [Data] {
        let url = Gate.repoRoot().appendingPathComponent("Tests/AuraCoreTests/Fixtures/round4-codex.ndjson")
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line -> Data? in
                guard let outer = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: outer) as? [String: Any],
                      let payload = obj["_payload"] as? [String: Any],
                      let inner = try? JSONSerialization.data(withJSONObject: payload)
                else { return nil }
                return inner
            }
    }

    @Test("18 筆逐筆解析：effect 對照探針欄位表；agent 貫穿之後一律 codex；反向涵蓋六個事件")
    func round4FixtureParsesAndMatchesProbeTable() throws {
        // 前提檢查（不依賴 T05，先確認 fixture 本身在磁碟上真的是 18 筆、能被
        // 既有的 HookPayload 解析——這半不用等 T05，先確認地基是穩的）。
        let payloads = try Self.loadPayloads()
        #expect(payloads.count == 18, "round4-codex.ndjson 應有 18 筆，實際 \(payloads.count)")
        var seenEvents: Set<String> = []
        for data in payloads {
            let p = try #require(HookPayload(data: data), "無法解析成 HookPayload")
            seenEvents.insert(p.hookEventName)
            #expect(SnapshotIO.isSafeSessionID(p.sessionID),
                    "round4 的 session_id（UUIDv7）必須通過既有的安全檔名檢查")
            let row = try #require(Self.probeTable.first { $0.event == p.hookEventName },
                                   "探針欄位表沒有這個事件：\(p.hookEventName)")
            #expect(p.effect == row.expectedEffect,
                    "\(p.hookEventName) 的 effect 應為 \(row.expectedEffect)，實際 \(p.effect)")
        }
        for row in Self.probeTable {
            #expect(seenEvents.contains(row.event),
                    "探針表列出 \(row.event)，但 round4 fixture 裡一次都沒出現")
        }

        #if AURA_CODEX_PENDING_T05
        for data in payloads {
            let p = try #require(HookPayload(data: data))
            let snapshot = MergeRules.merge(p, into: nil, pid: nil, pidStartedAt: nil,
                                            agent: .codex, now: Date())
            #expect(snapshot.agent == Agent.codex.storedRawValue,
                    "--agent codex 貫穿之後，狀態檔的 agent 欄位必須是 \"codex\"，實際 \(String(describing: snapshot.agent))")
        }
        #else
        Issue.record("""
            待 T05：MergeRules.merge(...) 尚未加上 agent: 參數（spec §4.1「5a」）——\
            agent 貫穿 into SessionSnapshot 那一半無法驗證。T05 落地後把本測試函式裡的 \
            #if AURA_CODEX_PENDING_T05 / #else / #endif 三行拿掉即可生效。
            """)
        #endif
    }
}
