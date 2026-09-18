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

    /// T04c（spec-reviewer M1）：`agentFlag` 是跟 `hookTimeoutSeconds` 同一族的自我一致倖存者
    /// ——reviewer 實測把它改成 `"--agent codexx"`，全量 808 條測試**零條**變紅，因為下面的
    /// 逐格 command 斷言原本跟 `CodexHooksJSON.agentFlag` 自己比較，常數改壞時兩邊一起變。
    /// 所以這裡與下面的逐格斷言都改成寫死字面 `"--agent codex"`，同 `hookTimeoutSeconds`
    /// 那格已經做對的處理。
    @Test("agentFlag 字面等於 \"--agent codex\"")
    func agentFlagIsPinnedToLiteral() {
        #expect(CodexHooksJSON.agentFlag == "--agent codex")
    }

    /// T02↔T04 接縫（spec-reviewer M1）：`CodexHooksJSON` 寫進 hooks.json 的旗標字面，
    /// 必須是 `AgentArgument.agent(from:)`（T02）真的認得的那個——兩份各自維護的字串，
    /// 只 specced 一邊就是「A 產出、B 消費」的接縫破洞（spec §4.2 接縫 lens）。這條同時擋住
    /// 兩個方向：改壞 `CodexHooksJSON.agentFlag`，或改壞 `Agent.codex.rawValue`／
    /// `AgentArgument` 的解析規則。
    @Test("產生器寫出去的旗標，解析器認得（T02↔T04 接縫）")
    func generatedFlagIsUnderstoodByTheParser() {
        let argv = CodexHooksJSON.agentFlag.split(separator: " ").map(String.init)
        #expect(AgentArgument.agent(from: argv) == .codex,
                "hooks.json 寫的是 \(CodexHooksJSON.agentFlag)，但 AgentArgument 解析不出 .codex")
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
            // 刻意寫死字面 "--agent codex"（不是 `CodexHooksJSON.agentFlag`）——見
            // `agentFlagIsPinnedToLiteral` 的 doc comment：跟常數本身比較會在常數被改壞
            // 時一起變質，讓「agentFlag 改成 codexx」的 mutation 全量零新紅通過。
            #expect(entry["command"] as? String == "\(Self.hookBinaryPath) --agent codex",
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

    /// `snippet(...)` 與 `json(...)` 同源（`snippet` 就是對 `json(...)` 的 UTF-8 文字轉換）
    /// ——這條守的是「兩者結構相同、snippet 沒有被改成另外手寫一份」，**不是**跳脫正確性
    /// （spec-reviewer m2：`snippet` 本身是對 `json(...)` 的無損轉換，位元組比對與結構比對
    /// 鑑別力相近，兩者都測不出跳脫壞掉——跳脫正確性由 `adversarialPathsRoundTrip` 守）。
    @Test("snippet 與 json 的乾淨路徑 round-trip 結構相同")
    func snippetRoundTripsToSameStructure() throws {
        let jsonRoot = try Self.parsedRoot()
        let snippetText = CodexHooksJSON.snippet(hookBinaryPath: Self.hookBinaryPath)
        let snippetData = try #require(snippetText.data(using: .utf8))
        let snippetObject = try JSONSerialization.jsonObject(with: snippetData)
        let snippetRoot = try #require(snippetObject as? [String: Any])
        #expect((snippetRoot as NSDictionary) == (jsonRoot as NSDictionary))
    }

    /// CX6③（spec-reviewer M2）：含空白／`"`／`\` 的路徑仍要產出合法 JSON、`command`
    /// round-trip 回原路徑——**不是理論情境**：R-10／D-s 規定 `.blockedByBundlePath
    /// (.unsupportedCharacter)` 仍要顯示 snippet，而那個 case 的定義就是路徑含這些字元之一，
    /// 所以生產環境**必然會**用這類路徑呼叫 `snippet(...)`／`json(...)`。
    ///
    /// 這條同時把 `json()` 的 `Data()` fallback「不可達」變成可觀測（spec-reviewer m1）：
    /// 若序列化真的因為某個字元失敗，`parsedRoot` 對空 `Data` 解析會 throw，測試會紅，
    /// 而不是靜默通過。
    @Test("含空白／引號／反斜線的路徑仍產出合法 JSON，且 command round-trip 回原路徑")
    func adversarialPathsRoundTrip() throws {
        let adversarialPaths = [
            "/Users/demo/My Apps/AgentAura.app/Contents/MacOS/aura-hook",
            "/Users/demo/Agent\"Aura.app/Contents/MacOS/aura-hook",
            "/Users/demo/Agent\\Aura.app/Contents/MacOS/aura-hook",
        ]
        for path in adversarialPaths {
            let root = try Self.parsedRoot(path)
            let hooks = try #require(root["hooks"] as? [String: Any])
            let event = try #require(EventMapping.codexEvents.sorted().first)
            let groups = try #require(hooks[event] as? [[String: Any]])
            let group = try #require(groups.first)
            let entries = try #require(group["hooks"] as? [[String: Any]])
            let entry = try #require(entries.first)
            #expect(entry["command"] as? String == "\(path) --agent codex",
                    "\(path)：command 應 round-trip 回原路徑加 --agent codex")
        }
    }
}
