import Testing
import Foundation
@testable import AuraCore

/// T03：`EventMapping.codexEvents` ＋ `Interrupt` 映射——spec §4.2「本 change 最容易踩的地方」。
///
/// 這五條 gate 守的是同一個接縫的五個面向：
/// - CX1／CX3：`codexEvents` 這個字面集合本身，以及它與既有 Claude 映射共用的那一半。
/// - CX2／CX5：`Interrupt`（Codex 獨有）**絕不能**讓 Claude 側 hooks.json 的全有全無解析中鏢。
/// - CX4：`Interrupt` 映射到 `.idle` 的定義域從 `codexOnlyEvents` 推導，不是寫死一個 case 名。
@Suite("Codex 事件集合與 Interrupt 映射（T03）")
struct CodexEventsTests {

    /// CX1：`codexEvents` 恰等於探針量到的 12 個字面名（F2）。
    ///
    /// 六個有真實 payload（探針 `codex exec` 實抓）：`SessionStart` `UserPromptSubmit`
    /// `PreToolUse` `PostToolUse` `Stop` `SessionEnd`。六個只有二進位字串 `HookEventsToml`
    /// 列舉、探針 session 從未觸發：`PermissionRequest` `Interrupt` `SubagentStart`
    /// `SubagentStop` `PreCompact` `PostCompact`。
    @Test("codexEvents 恰等於 F2 量到的 12 個字面名")
    func codexEventSetIsPinnedToProbe() {
        let realPayloadEvidence: Set<String> = [
            "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SessionEnd",
        ]
        let binaryStringOnlyEvidence: Set<String> = [
            "PermissionRequest", "Interrupt", "SubagentStart", "SubagentStop", "PreCompact", "PostCompact",
        ]
        #expect(realPayloadEvidence.isDisjoint(with: binaryStringOnlyEvidence),
                "測試前提壞了：兩種證據強度的樣本集不該重疊")
        #expect(EventMapping.codexEvents == realPayloadEvidence.union(binaryStringOnlyEvidence),
                "codexEvents 應恰等於 F2 的 12 個字面名（6 個有真實 payload ＋ 6 個只有二進位字串列舉）")
    }

    /// CX2：`Interrupt` 絕不可進入 `handledEvents`。
    ///
    /// 一旦進去，既有 `registeredEventsMatchHandledEvents`（`PluginWiringTests.swift`）那條
    /// 雙向等式會要求 Claude 側 `plugin/hooks/hooks.json` 也註冊 `Interrupt`——而 Claude Code
    /// 對 hooks.json 是**全有全無解析**，從未認得過這個事件名，整份 hooks 對 Claude 使用者
    /// 會靜默失效。
    @Test("Interrupt（以及未來任何 codexOnlyEvents）絕不可進入 handledEvents")
    func interruptNeverEntersHandledEvents() {
        let leaked = EventMapping.handledEvents.intersection(EventMapping.codexOnlyEvents)
        #expect(leaked.isEmpty, """
            Codex 專屬事件混進了 handledEvents：\(leaked.sorted())。
            Claude Code 對 hooks.json 是全有全無解析——這些事件一旦被要求註冊，
            plugin/hooks/hooks.json 會被 Claude Code 整份拒載，
            產品對 Claude 使用者完全停止運作。
            （本機 validate --strict 只給 warning，不構成反證——整份拒載是實測於
            另一個 Claude Code 版本，見 codexOnlyEvents 的 doc comment。）
            """)
    }

    /// CX3：`codexEvents − codexOnlyEvents` 的 11 個事件全部沿用既有 Claude 映射——
    /// 逐一 `⊆ handledEvents`，且 `effect` 非 `.noChange`（沒有映射的事件會落到
    /// `default: .noChange`，看起來像「處理過」其實是雜訊）。
    @Test("codexEvents 扣掉 codexOnlyEvents 之後全部沿用既有 Claude 映射")
    func codexSharedEventsReuseClaudeMapping() {
        let shared = EventMapping.codexEvents.subtracting(EventMapping.codexOnlyEvents)
        #expect(!shared.isEmpty, "測試前提壞了：codexEvents 應該有大部分事件沿用既有映射")
        for event in shared.sorted() {
            #expect(EventMapping.handledEvents.contains(event),
                    "\(event) 應沿用既有 Claude 映射，卻不在 handledEvents 裡")
            #expect(EventMapping.effect(forEvent: event) != .noChange,
                    "\(event) 落到 .noChange，等於沒有真的映射")
        }
    }

    /// CX4：`codexOnlyEvents`（目前只有 `Interrupt`）逐一映射到 `.setActivity(.idle)`。
    ///
    /// 定義域**從 `codexOnlyEvents` 推導**，不是寫死 `"Interrupt"` 這個字面——這樣往後
    /// 若 `codexOnlyEvents` 多一個成員，這條 gate 自動涵蓋它，不必記得回來加一行。
    ///
    /// `round4-codex.ndjson` 零筆 `Interrupt` 樣本（`SessionStart` 4／`UserPromptSubmit` 4／
    /// `Stop` 4／`SessionEnd` 4／`PreToolUse` 1／`PostToolUse` 1），所以少了這條 gate，
    /// 刪掉 `effect` 裡的 `case "Interrupt"` 整行會讓其他所有 gate 維持全綠——這條是
    /// 唯一守住這個映射的測試。
    @Test("codexOnlyEvents 逐一映射到 .setActivity(.idle)")
    func codexOnlyEventsMapToIdle() {
        #expect(!EventMapping.codexOnlyEvents.isEmpty, "測試前提壞了：codexOnlyEvents 不該是空集合")
        for event in EventMapping.codexOnlyEvents.sorted() {
            #expect(EventMapping.effect(forEvent: event) == .setActivity(.idle),
                    "\(event) 應映射到 .setActivity(.idle)")
        }
    }

    /// CX5：Claude 側 `plugin/hooks/hooks.json`（從磁碟讀）不得含任何 `codexOnlyEvents`。
    ///
    /// 獨立於 CX2／`registeredEventsMatchHandledEvents` 那條雙向等式——直接檢查磁碟上的
    /// 檔案，就算未來有人繞過 `handledEvents` 直接手改 hooks.json，這條還是守得住。
    @Test("Claude 側 hooks.json 不含任何 codexOnlyEvents")
    func claudeHooksJSONHasNoInterrupt() throws {
        let registered = Set(try PluginWiringTests.hooksJSON().keys)
        #expect(registered.count == EventMapping.handledEvents.count,
                "hooks.json 讀出 \(registered.count) 個事件——gate 不能空跑")
        let leaked = registered.intersection(EventMapping.codexOnlyEvents)
        #expect(leaked.isEmpty,
                "plugin/hooks/hooks.json 含有 Codex 專屬事件：\(leaked.sorted())")
    }
}
