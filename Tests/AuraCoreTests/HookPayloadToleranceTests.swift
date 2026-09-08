import Testing
import Foundation
@testable import AuraCore

/// 兩個系統性掃描，各自驗證不同的事，不可互相取代：
/// `extractionMatchesRawValues` 驗「好資料上提取正確」，
/// `perFieldCorruptionTolerance` 驗「壞資料不會拖垮解析」。
@Suite("HookPayload 系統性欄位掃描")
struct HookPayloadToleranceTests {

    /// **提取正確性掃描。**
    ///
    /// 對每個欄位問：「當真實 payload 裡有合法值時，屬性有沒有解析出來？」
    /// 抓的是「欄位存在卻被讀成 nil」這一類 —— 例如 key 名寫錯、巢狀路徑走錯、
    /// `nonEmpty` 誤把合法值濾掉。
    ///
    /// 這個測試**不破壞任何東西**；損壞容忍度是 `perFieldCorruptionTolerance` 的職責。
    /// 兩者保證不同的事，不可互相取代。
    ///
    /// 已知邊界：它只運動 corpus 裡實際出現過的 key，所以 `end_reason` 與
    /// `to_model`（防禦性的替代名，現實從未產出）碰不到 —— 那兩個由
    /// `reasonFieldTolerance` 與 `modelFromPostModelSwitch` 覆蓋。
    /// **看到「重複的」手工測試不要刪，它們正好覆蓋 corpus-derived 碰不到的部分。**
    @Test("真實 payload 有合法值的欄位，都必須被解析出來")
    func extractionMatchesRawValues() throws {
        struct FieldProbe {
            let name: String
            let hasRawValue: ([String: Any]) -> Bool
            let propertyValue: (HookPayload) -> Any?
        }

        let probes: [FieldProbe] = [
            .init(name: "cwd", hasRawValue: { ($0["cwd"] as? String)?.isEmpty == false }, propertyValue: { $0.cwd }),
            .init(name: "permissionMode", hasRawValue: { ($0["permission_mode"] as? String)?.isEmpty == false }, propertyValue: { $0.permissionMode }),
            .init(name: "source", hasRawValue: { ($0["source"] as? String)?.isEmpty == false }, propertyValue: { $0.source }),
            .init(name: "reason", hasRawValue: { (($0["reason"] as? String) ?? ($0["end_reason"] as? String))?.isEmpty == false }, propertyValue: { $0.reason }),
            .init(name: "toolName", hasRawValue: { ($0["tool_name"] as? String)?.isEmpty == false }, propertyValue: { $0.toolName }),
            .init(name: "toolDescription", hasRawValue: { (($0["tool_input"] as? [String: Any])?["description"] as? String)?.isEmpty == false }, propertyValue: { $0.toolDescription }),
            .init(name: "toolDurationMs", hasRawValue: { $0["duration_ms"] is Int }, propertyValue: { $0.toolDurationMs }),
            .init(name: "model", hasRawValue: { (($0["model"] as? String) ?? ($0["to_model"] as? String))?.isEmpty == false }, propertyValue: { $0.model }),
            .init(name: "notificationType", hasRawValue: { ($0["notification_type"] as? String)?.isEmpty == false }, propertyValue: { $0.notificationType }),
            .init(name: "notificationMessage", hasRawValue: { ($0["message"] as? String)?.isEmpty == false }, propertyValue: { $0.notificationMessage }),
            .init(name: "lastMessage", hasRawValue: { ($0["last_assistant_message"] as? String)?.isEmpty == false }, propertyValue: { $0.lastMessage }),
            .init(name: "agentID", hasRawValue: { ($0["agent_id"] as? String)?.isEmpty == false }, propertyValue: { $0.agentID }),
            .init(name: "agentType", hasRawValue: { ($0["agent_type"] as? String)?.isEmpty == false }, propertyValue: { $0.agentType }),
        ]

        let all = try Fixtures.rawEvents(named: "round1")
            + Fixtures.rawEvents(named: "round1b")
            + Fixtures.rawEvents(named: "round2")
        #expect(all.count == 141)

        var exercised: Set<String> = []
        var combinations = 0
        for json in all {
            guard let p = HookPayload(json: json) else {
                Issue.record("真實 payload 解析失敗：\(json["hook_event_name"] ?? "?")")
                continue
            }
            for probe in probes where probe.hasRawValue(json) {
                combinations += 1
                #expect(probe.propertyValue(p) != nil,
                        "\(probe.name) 原始值存在卻沒被解析出來（event: \(json["hook_event_name"] ?? "?"))")
                exercised.insert(probe.name)
            }
        }

        for probe in probes {
            #expect(exercised.contains(probe.name),
                    "真實 fixture 裡沒有任何 payload 讓 \(probe.name) 有值 —— 這個欄位的覆蓋率是空的")
        }
        #expect(combinations > 0)
    }

    /// **損壞容忍度掃描 —— 這個型別存在的核心主張。**
    ///
    /// `HookPayload` 刻意不用 `Codable`，理由是「字典讀取容忍未知／缺失／改型的
    /// 欄位，而 `Codable` 會讓整個 decode 失敗」。**那句話就是這個測試在驗的東西。**
    ///
    /// 從真實 payload 的實際 key 推導（不是手工清單，所以新增欄位自動涵蓋）：
    /// 逐一移除、逐一換成 5 種不符型別，斷言只有 `hook_event_name` 與 `session_id`
    /// 是必要的，其餘任何欄位壞掉都不得讓整個解析失敗（該欄位變 nil 即可）。
    ///
    /// **與 `extractionMatchesRawValues` 不重疊，兩者都不能刪**：那個驗「好資料上
    /// 提取正確」，這個驗「壞資料不會拖垮整體」。曾經有一版把兩者混為一談，
    /// 結果核心主張對 14 個 optional 欄位中的 12 個完全沒有測試。
    @Test("逐一破壞真實 payload 的每個欄位：只有兩個是必要的")
    func perFieldCorruptionTolerance() throws {
        // 三份 fixture 全用，**不取樣**。
        //
        // 曾經有一版寫 `where i % 8 == 0`（為了控制測試時間），它靜默掏空了覆蓋：
        // 9 個這個型別真的會讀的 key 完全沒有損壞測試，因為那個 stride 剛好錯過
        // 它們在 corpus 裡的每一次出現 —— 其中包括 `error` 與 `is_interrupt`
        // （`toolError` / `isInterrupt` 的來源），它們唯一的出現位置在 round2 的
        // index 66，而 66 % 8 == 2。
        let reals = try Fixtures.rawEvents(named: "round1")
            + Fixtures.rawEvents(named: "round1b")
            + Fixtures.rawEvents(named: "round2")
        let required: Set<String> = ["hook_event_name", "session_id"]
        var checked: Set<String> = []

        for json in reals {
            for key in json.keys {
                checked.insert(key)

                var dropped = json
                dropped.removeValue(forKey: key)
                if required.contains(key) {
                    #expect(HookPayload(json: dropped) == nil,
                            "\(key) 是必要欄位，移除後應回 nil")
                } else {
                    #expect(HookPayload(json: dropped) != nil,
                            "\(key) 非必要，移除後仍應解析成功")
                }

                for wrong: Any in [NSNull(), 42, ["nested": [1, 2, 3]], [1, 2, 3], true] {
                    var retyped = json
                    retyped[key] = wrong
                    if required.contains(key) {
                        #expect(HookPayload(json: retyped) == nil,
                                "\(key) 型別錯時應回 nil")
                    } else {
                        #expect(HookPayload(json: retyped) != nil,
                                "\(key) 型別錯時不該讓整個解析失敗，該欄位變 nil 即可")
                    }
                }
            }
        }
        // 斷言涵蓋 corpus 裡出現過的**每一個** key，而不是「至少 N 個」——
        // `>=` 無法察覺取樣把某些 key 整批跳過。
        let allCorpusKeys = Set(reals.flatMap { $0.keys })
        #expect(checked == allCorpusKeys,
                "漏掃的 key：\(allCorpusKeys.subtracting(checked).sorted())")

        // 特別點名這個型別會讀、且 corpus 有的 key —— 最容易被取樣跳過的那一批
        for key in ["error", "is_interrupt", "message", "model",
                    "notification_type", "reason", "source", "tool_input"] {
            if allCorpusKeys.contains(key) {
                #expect(checked.contains(key), "\(key) 在 corpus 裡卻沒被掃到")
            }
        }
    }
}
