import Testing
import Foundation
@testable import AuraCore

/// G9b（外部錨點，spec §6.3）：`Jargon` 的映射表必須涵蓋
/// `Tests/AuraCoreTests/Fixtures/*.ndjson` 裡**實際出現過**的每一個
/// `permission_mode`／`effort.level`／`model` 值 —— 不是涵蓋設計時想到的值。
/// 這條才擋得住上游新增值（例如 r1 漏掉的 `auto`）。
///
/// 掃磁碟上的 `Fixtures` 目錄，不是 `Bundle.module` 裡點名的單一檔案——新增
/// fixture 檔要自動被涵蓋，不必回頭改這條 gate。讀不到／解析不出來一律
/// `throw`（同 `AppLayerSourceScanTests` 的慣例），不能讓壞掉的 fixture 看起來乾淨。
@Suite("Jargon 涵蓋 fixture 裡的每一個真值（G9b／G9c）")
struct FixtureCodeAnchorTests {

    struct ScanResult {
        let scannedFiles: Int
        let permissionModes: Set<String>
        let effortLevels: Set<String>
        let models: Set<String>
    }

    static func scanFixtures() throws -> ScanResult {
        let dir = Gate.repoRoot().appendingPathComponent("Tests/AuraCoreTests/Fixtures")
        let all = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let files = all.filter { $0.pathExtension == "ndjson" }
        guard !files.isEmpty else {
            throw Gate.GateFailure("Fixtures 目錄（\(dir.path)）讀不到任何 .ndjson —— gate 不能空跑")
        }

        var permissionModes: Set<String> = [], effortLevels: Set<String> = [], models: Set<String> = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)   // 讀不到 → 大聲紅
            for line in text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                guard let data = String(line).data(using: .utf8),
                      let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { throw Gate.GateFailure("解析失敗（\(file.lastPathComponent)）：\(line.prefix(80))") }
                let payload = obj["_payload"] as? [String: Any] ?? obj
                if let v = HookPayload.string(payload["permission_mode"]) { permissionModes.insert(v) }
                if let v = HookPayload.effortLevel(payload["effort"]) { effortLevels.insert(v) }
                if let v = HookPayload.nonEmpty(payload["model"]) { models.insert(v) }
            }
        }
        return ScanResult(scannedFiles: files.count, permissionModes: permissionModes,
                          effortLevels: effortLevels, models: models)
    }

    @Test("permission_mode：fixture 裡出現過的每一個值都在 permissionModeMap 裡（含 auto）")
    func everyFixturePermissionModeIsMapped() throws {
        let result = try Self.scanFixtures()
        #expect(result.scannedFiles >= 3, "只掃到 \(result.scannedFiles) 個 .ndjson —— gate 不能空跑")
        #expect(!result.permissionModes.isEmpty, "fixture 裡沒掃到任何 permission_mode —— 解析可能壞了")
        #expect(result.permissionModes.contains("auto"), "141 個真實 payload 裡最常見的值 auto 應該要出現在 fixture 裡")
        for v in result.permissionModes.sorted() {
            #expect(Jargon.permissionModeMap[v] != nil,
                    "fixture 裡出現過 permission_mode=\"\(v)\"，但 Jargon.permissionModeMap 沒有它的人話對應")
        }
    }

    @Test("effort.level：fixture 裡出現過的每一個值都在 effortMap 裡")
    func everyFixtureEffortLevelIsMapped() throws {
        let result = try Self.scanFixtures()
        #expect(!result.effortLevels.isEmpty, "fixture 裡沒掃到任何 effort.level —— 解析可能壞了")
        for v in result.effortLevels.sorted() {
            #expect(Jargon.effortMap[v] != nil,
                    "fixture 裡出現過 effort.level=\"\(v)\"，但 Jargon.effortMap 沒有它的人話對應")
        }
    }

    @Test("model：fixture 裡出現過的每一個值經 Jargon.model 後不再是原始代碼字")
    func everyFixtureModelIsMapped() throws {
        let result = try Self.scanFixtures()
        #expect(!result.models.isEmpty, "fixture 裡沒掃到任何 model —— 解析可能壞了")
        for v in result.models.sorted() {
            #expect(Jargon.model(v) != v,
                    "fixture 裡出現過 model=\"\(v)\"，但 Jargon.model 原樣回傳，沒有翻成人話")
        }
    }

    // ---- G9c（wired，S1-Q5）：用 fixture 真值建 SessionState，證明呼叫點真的接上 Jargon ----

    @Test("PanelViewModel.rows(from:) 的 meta 不回顯任何原始代碼字（wired）")
    func metaNeverEchoesKnownCode() throws {
        let result = try Self.scanFixtures()
        // .sorted().first 而非 .first：Set 迭代順序不保證穩定，測試輸出要可重現。
        let model = try #require(result.models.sorted().first, "fixture 裡沒有 model 值可用")
        let mode = try #require(result.permissionModes.sorted().first, "fixture 裡沒有 permission_mode 值可用")
        let effort = try #require(result.effortLevels.sorted().first, "fixture 裡沒有 effort.level 值可用")

        let s = SessionState(id: "s", projectName: "P",
                             permissionMode: mode, effort: effort, model: model,
                             activity: .working, mainActivity: .working, subActivity: nil,
                             currentTool: nil, subagentTool: nil, toolDurationMs: nil,
                             turnStartedAt: nil, subagents: [:], toolFailures: 0,
                             lastMessage: nil, errorType: nil, toolError: nil,
                             liveness: .alive(pid: 1), updatedAt: Date())

        let meta = PanelViewModel.rows(from: [s]).first!.meta
        #expect(!meta.contains(model), "meta 回顯了原始 model 代碼字「\(model)」，實際：\(meta)")
        #expect(!meta.contains(mode), "meta 回顯了原始 permission_mode 代碼字「\(mode)」，實際：\(meta)")
        #expect(!meta.contains(effort), "meta 回顯了原始 effort.level 代碼字「\(effort)」，實際：\(meta)")
    }
}
