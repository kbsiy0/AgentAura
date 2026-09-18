import Testing
import Foundation
@testable import AuraCore

/// T04a：`CodexHooksJSON`——逐字 F14（唯一數值偏離 `timeout`），spec §4.3／CX6。
///
/// 不抽樣：12 個事件逐一逐字比對，抽樣有 11/12 的機率看不到某個事件被寫死不同值的特例。
@Suite("CodexHooksJSON 逐字比對 F14（CX6）")
struct CodexHooksJSONTests {

    static let hookBinaryPath = "/Applications/AgentAura.app/Contents/MacOS/aura-hook"

    /// 把 `CodexHooksJSON.json(...)` 解析成 `[String: Any]`——型別窄化失敗直接讓測試
    /// 中止（`#require`），比靜默回傳空字典更早暴露問題。
    private static func parsedRoot(_ path: String = hookBinaryPath) throws -> [String: Any] {
        let data = CodexHooksJSON.json(hookBinaryPath: path)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    /// 定義域非空守衛：`codexEvents` 不能是空集合，否則下面每一格斷言都在空跑。
    @Test("codexEvents 定義域非空")
    func domainIsNonEmpty() {
        #expect(!EventMapping.codexEvents.isEmpty)
    }

    /// CX6①：`hooks` 物件的鍵集合恰等於 `EventMapping.codexEvents`。
    @Test("鍵集合恰等於 codexEvents")
    func keySetMatchesCodexEvents() throws {
        let root = try Self.parsedRoot()
        let hooks = try #require(root["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == EventMapping.codexEvents)
    }

    /// `hookTimeoutSeconds` 本身釘死在字面 `3`（R-4）——**不可**只跟自己比較：
    /// 若下面的逐格斷言改成 `== CodexHooksJSON.hookTimeoutSeconds`，把常數本身改回 5
    /// 的 mutation 會讀到同一個被改壞的常數，兩邊一起變、測試全綠卻什麼都沒守到
    /// （自我一致的常數倖存者）。所以這裡與下面的逐格斷言都寫死字面 `3`。
    @Test("hookTimeoutSeconds 字面等於 3（R-4，對 F14 唯一的數值偏離，F14 量到 5）")
    func hookTimeoutSecondsIsPinnedToThreeLiteral() {
        #expect(CodexHooksJSON.hookTimeoutSeconds == 3)
    }

    /// CX6②：12 個事件逐一逐字等於 F14 的形狀——`matcher: ""`、`type: "command"`、
    /// `command` 是裸路徑加 `--agent codex`、`timeout` 字面等於 `3`，
    /// 且沒有多出 F14 未測欄位（例如 `async`）。
    @Test("12 個事件逐一逐字等於 F14")
    func everyEntryMatchesF14Verbatim() throws {
        let root = try Self.parsedRoot()
        let hooks = try #require(root["hooks"] as? [String: Any])
        #expect(!EventMapping.codexEvents.isEmpty, "CX6 的定義域不能空跑")
        for event in EventMapping.codexEvents.sorted() {
            let groups = try #require(hooks[event] as? [[String: Any]], "\(event) 的值型別不對")
            #expect(groups.count == 1, "\(event) 應恰有一個 group")
            let group = try #require(groups.first)
            #expect(group["matcher"] as? String == "",
                    "\(event) 的 matcher 應為空字串（F14 未測欄，不可省略）")
            #expect(group.keys.sorted() == ["hooks", "matcher"],
                    "\(event) 的 group 不可多出未測欄位")
            let entries = try #require(group["hooks"] as? [[String: Any]])
            #expect(entries.count == 1, "\(event) 應恰有一個 hook entry")
            let entry = try #require(entries.first)
            #expect(entry["type"] as? String == "command")
            #expect(entry["command"] as? String == "\(Self.hookBinaryPath) \(CodexHooksJSON.agentFlag)",
                    "\(event) 的 command 應為裸路徑加 --agent codex，不加引號")
            // 刻意寫死字面 3（不是 `CodexHooksJSON.hookTimeoutSeconds`）——見
            // `hookTimeoutSecondsIsPinnedToThreeLiteral` 的 doc comment：跟常數本身比較
            // 會在常數被改壞時一起變質，讓「timeout 改回 5」的 mutation 全綠通過。
            #expect(entry["timeout"] as? Int == 3,
                    "\(event) 的 timeout 應恰為 3（R-4，對 F14 唯一的數值偏離，F14 量到 5）")
            #expect(entry.keys.sorted() == ["command", "timeout", "type"],
                    "\(event) 的 entry 不可多出 async 等 F14 未測欄位")
        }
    }

    /// CX6③：`snippet(...)` 是 `json(...)` 的文字形式——乾淨路徑下，把兩者各自解析回物件，
    /// 結構必須相同（round-trip 負對照）。
    @Test("snippet 與 json 的乾淨路徑 round-trip 結構相同")
    func snippetRoundTripsToSameStructure() throws {
        let jsonRoot = try Self.parsedRoot()
        let snippetText = CodexHooksJSON.snippet(hookBinaryPath: Self.hookBinaryPath)
        let snippetData = try #require(snippetText.data(using: .utf8))
        let snippetObject = try JSONSerialization.jsonObject(with: snippetData)
        let snippetRoot = try #require(snippetObject as? [String: Any])
        #expect((snippetRoot as NSDictionary) == (jsonRoot as NSDictionary))
    }
}
