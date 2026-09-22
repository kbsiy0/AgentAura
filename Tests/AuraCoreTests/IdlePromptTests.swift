import Testing
import Foundation
@testable import AuraCore
@testable import AuraHookFile   // SnapshotIO（二進位 wired gate 讀狀態檔）

/// `Notification(idle_prompt)` 不得把 session 變成 `waiting`。
///
/// 實測（2026-09-09 14:2x，使用者截圖）：一輪結束、60 秒沒收到新 prompt，Claude Code 送
/// `{"notification_type":"idle_prompt","message":"Claude is waiting for your input"}`。
/// 原 spec §2.2.1 把它歸為「需要使用者」→ 橘燈呼吸。後果：**每一個講完話的 session 60 秒後
/// 都會變橘**——「動＝需要你」（R4）失效，跟 §2.4.1 那條 Deny 假陽性是同一族：早就沒事的
/// session 讓 icon 一直喊有人在等你。
///
/// `idle_prompt` 的語意是「我講完了、你還沒講」，那是 `done` 的自然延續，不是「你被擋住」。
/// 真正擋住的情況（`permission_prompt` / `agent_needs_input` / `elicitation_*`）仍映射 waiting。
@Suite("idle_prompt 不是 waiting（2026-09-09 實測假陽性）")
struct IdlePromptTests {

    @Test("EventMapping：idle_prompt → noChange")
    func idlePromptIsNoChange() {
        #expect(EventMapping.effect(forEvent: "Notification", notificationType: "idle_prompt") == .noChange,
                "idle_prompt 只代表「你還沒下新 prompt」，不是有人在等你批准")
        #expect(!EventMapping.notificationTypesNeedingUser.contains("idle_prompt"),
                "matcher 從這個集合推導；留在裡面 hooks.json 就會繼續收它")
    }

    /// 使用者可見的契約：Stop 之後的 idle_prompt 必須讓燈**停在綠**（done），不能變橘。
    @Test("MergeRules：Stop 之後的 idle_prompt 保住 done，不變 waiting")
    func idlePromptAfterStopKeepsDone() throws {
        let t0 = Date(timeIntervalSince1970: 1_788_930_000)
        func p(_ json: [String: Any]) -> HookPayload {
            HookPayload(json: json.merging(["session_id": "s-idle"]) { a, _ in a })!
        }
        var s = MergeRules.merge(p(["hook_event_name": "Stop", "last_message": "做完了"]),
                                 into: nil, pid: 1, pidStartedAt: 1, agent: .claude, now: t0)
        #expect(s.mainActivity == .done, "前提：Stop → done")

        s = MergeRules.merge(p(["hook_event_name": "Notification",
                                "notification_type": "idle_prompt",
                                "message": "Claude is waiting for your input"]),
                             into: s, pid: 1, pidStartedAt: 1, agent: .claude, now: t0.addingTimeInterval(60))
        #expect(s.mainActivity == .done, """
            idle_prompt 把 done 改成了 \(s.mainActivity)。使用者會在每一個講完話的 session
            60 秒後看到橘燈，而那個 session 根本沒有在等任何批准。
            """)
        #expect(s.notificationType == "idle_prompt", "欄位仍要帶過來（面板可顯示），只是不改 activity")
        #expect(s.notificationMessage == "Claude is waiting for your input",
                "message 也帶過來——它是 PanelViewModel.headline 對 waiting 的第二順位來源（既有接縫，見 review M1）")
    }

    /// **出貨產物路徑**：映射編在 `aura-hook` 二進位裡，in-process 測試證明的是規則不是產物。
    /// 真 spawn 二進位：Stop → Notification(idle_prompt)，狀態檔必須停在 done。
    /// （spec §2.2.1：「matcher 支援度可能隨版本變動，payload 內的型別檢查才是正確性保證」——
    /// 這條就是那個保證的 wired gate；matcher 濾掉事件只是第一層。）
    @Test("aura-hook 二進位：Stop 之後餵 idle_prompt，狀態檔仍是 done")
    func binaryKeepsDoneAfterIdlePrompt() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-idle-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        func fire(_ payload: String) throws {
            let p = Process()
            p.executableURL = try AuraHookCLITests.binaryURL()
            p.environment = ProcessInfo.processInfo.environment.merging(["AGENTAURA_ROOT": root.path]) { _, n in n }
            let inPipe = Pipe(); p.standardInput = inPipe
            p.standardOutput = Pipe(); p.standardError = Pipe()
            try p.run()
            inPipe.fileHandleForWriting.write(Data(payload.utf8)); try inPipe.fileHandleForWriting.close()
            p.waitUntilExit()
            #expect(p.terminationStatus == 0, "aura-hook 一律 exit 0")
        }
        // T10b：兩次真的 spawn 一起經過 SpawnGate。
        try await SpawnGate.shared.run {
            try fire(#"{"hook_event_name":"Stop","session_id":"bin-idle","last_message":"做完了"}"#)
            try fire(#"{"hook_event_name":"Notification","session_id":"bin-idle","notification_type":"idle_prompt","message":"Claude is waiting for your input"}"#)
        }
        let s = try #require(SnapshotIO.read(sessionID: "bin-idle", root: root))
        #expect(s.mainActivity == .done, "二進位把 idle_prompt 寫成了 \(s.mainActivity)——舊 plugin/bin/aura-hook 沒重建就會是這樣")
        #expect(s.notificationType == "idle_prompt")
    }

    /// 反向對照：真正需要使用者的型別仍是 waiting —— 這條測試不是把 Notification 整個關掉。
    @Test("對照：permission_prompt 仍是 waiting")
    func permissionPromptStillWaiting() {
        #expect(EventMapping.effect(forEvent: "Notification", notificationType: "permission_prompt")
                == .setActivity(.waiting))
    }
}
