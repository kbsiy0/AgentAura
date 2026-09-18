import Testing
import Foundation
@testable import AuraCore
@testable import AuraHookFile

/// CX38（R-8 不變式 2，T05c／T05d 拆檔）：拆自 `EndToEndWiredGateTests`——加上 M1 的
/// CX9 生產層鏡像後那個檔案會突破 300 行上限。重用它的 `makeRoot()`／
/// `fireHook(_:root:)`（已改成 `static`）與 `fireHookWithArgv(_:root:argv:)`，
/// 不複製一份建根／spawn 邏輯。同樣用**真的** aura-hook 二進位，真 spawn 走 `SpawnGate`。
@Suite("端到端 wired-gate：雙 agent（CX38）", .serialized)
struct EndToEndDualAgentTests {

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
        let root = try EndToEndWiredGateTests.makeRoot()

        func fireClaude() async throws {
            for dict in claudeEvents {
                try await EndToEndWiredGateTests.fireHook(
                    String(decoding: try Fixtures.jsonData(dict), as: UTF8.self), root: root)
            }
        }
        func fireCodex() async throws {
            for dict in codexEvents {
                _ = try await EndToEndWiredGateTests.fireHookWithArgv(
                    String(decoding: try Fixtures.jsonData(dict), as: UTF8.self),
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
