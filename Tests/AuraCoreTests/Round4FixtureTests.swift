import Testing
import Foundation
@testable import AuraCore
@testable import AuraHookFile

/// codex-support T01 骨架（CX13，**T05 已解除**）：`round4-codex.ndjson` 的 18 筆逐筆解析，
/// 期望值來自 `docs/2026-09-18-codex-hook-probe.md` 的「每種事件的欄位」表（F2，該文件
/// 第 36–45 行），**不是從 `HookPayload`／`EventMapping` 現有行為反推**——round4 的
/// 6 種事件全部是既有 `handledEvents` 的既有映射（D-e：Codex 只在 `Interrupt` 上加新
/// 東西），所以下面 `probeTable` 的期望值就是 `Sources/AuraCore/EventMapping.swift`
/// 今天已經寫死的那六條規則本身，是讀原始碼寫下來的，不是呼叫它再拿結果比對自己。
///
/// **歷史記錄（T01 → T05）**：`MergeRules.merge(...)` 原本沒有 `agent:` 參數，下面
/// 「agent 貫穿之後一律 codex」那段真斷言在 T01 落地時關在一個編譯期旗標的條件區塊裡
/// （Swift 對不啟用的分支不做型別檢查，所以引用尚不存在的簽章不會讓整個 test target
/// 編不過），另一個分支用 `Issue.record` 頂著讓測試當時確實是 RED。T05 落地
/// `MergeRules.merge(agent:)` 之後已拿掉那組條件編譯與 `Issue.record`，只留原本
/// 條件為真那一側的真斷言（T12 的全 repo 殘留掃描負責確認沒有旗標殘留）。
@Suite("round4-codex.ndjson 覆蓋（CX13）")
struct Round4FixtureTests {

    /// `fields`（T01b review M3）：逐字抄 `docs/2026-09-18-codex-hook-probe.md` 第 36–45
    /// 行「每種事件的欄位」表，把文件裡的「上述」展開成具體欄位名——不是從
    /// `HookPayload` 反推。這是**跨事件聯集**用的欄位集合（見下方反向斷言），不是
    /// 「這個事件的樣本恰好只有這些鍵」的窮盡宣告，所以某一列的欄位在別的事件才實際
    /// 出現（例如 `source` 只出現在這次 round4 捕捉到的 `SessionStart` 樣本裡，
    /// `UserPromptSubmit` 沒有）不影響這條防線要抓的東西。
    struct ProbeRow { let event: String; let expectedEffect: EventEffect; let fields: [String] }

    static let probeTable: [ProbeRow] = [
        ProbeRow(event: "SessionStart", expectedEffect: .setActivity(.idle),
                 fields: ["session_id", "cwd", "hook_event_name", "model", "permission_mode",
                          "source", "transcript_path"]),
        ProbeRow(event: "UserPromptSubmit", expectedEffect: .setActivity(.working),
                 fields: ["session_id", "cwd", "hook_event_name", "model", "permission_mode",
                          "source", "transcript_path", "turn_id", "prompt"]),
        ProbeRow(event: "PreToolUse", expectedEffect: .setActivity(.working),
                 fields: ["session_id", "cwd", "hook_event_name", "model", "permission_mode",
                          "source", "transcript_path", "turn_id", "prompt",
                          "tool_name", "tool_input", "tool_use_id"]),
        ProbeRow(event: "PostToolUse", expectedEffect: .setActivity(.working),
                 fields: ["session_id", "cwd", "hook_event_name", "model", "permission_mode",
                          "source", "transcript_path", "turn_id", "prompt",
                          "tool_name", "tool_input", "tool_use_id", "tool_response"]),
        ProbeRow(event: "Stop", expectedEffect: .setActivity(.done),
                 fields: ["session_id", "cwd", "hook_event_name", "model", "permission_mode",
                          "turn_id", "transcript_path", "last_assistant_message", "stop_hook_active"]),
        ProbeRow(event: "SessionEnd", expectedEffect: .sessionEnded,
                 fields: ["session_id", "cwd", "hook_event_name", "transcript_path", "reason"]),
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

    @Test("18 筆逐筆解析：effect 對照探針欄位表；agent 貫穿之後一律 codex；反向涵蓋六個事件與每個欄位")
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

        // 反向斷言升級到**欄位層**（T01b review M3）：探針表提到的每個欄位，至少要在
        // fixture 的某一筆樣本裡出現過一次——這才是防「有人把 fixture 每一筆的某個
        // 欄位都拿掉，只留下事件本身」的那道防線。事件層（上面 seenEvents）看不到
        // 這種弱化：拿掉每一筆的 model 欄位，事件仍然都在、事件層全綠，但那正好會讓
        // `FixtureCodeAnchorTests.everyFixtureModelIsMapped`（跨層錨點 gate）從紅
        // 變綠——用縮小證據來消滅一條紅燈，是這個專案最該防的那種弱化，只有欄位層
        // 看得到它。
        var seenFields: Set<String> = []
        for data in payloads {
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            seenFields.formUnion(obj.keys)
        }
        let allDocumentedFields = Set(Self.probeTable.flatMap(\.fields))
        for field in allDocumentedFields.sorted() {
            #expect(seenFields.contains(field),
                    "探針欄位表提到欄位 \"\(field)\"，但 round4 fixture 裡一次都沒出現過")
        }

        for data in payloads {
            let p = try #require(HookPayload(data: data))
            let snapshot = MergeRules.merge(p, into: nil, pid: nil, pidStartedAt: nil,
                                            agent: .codex, now: Date())
            #expect(snapshot.agent == Agent.codex.storedRawValue,
                    "--agent codex 貫穿之後，狀態檔的 agent 欄位必須是 \"codex\"，實際 \(String(describing: snapshot.agent))")
        }
    }
}
