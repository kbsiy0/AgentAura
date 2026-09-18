import Foundation
import AuraCore
import AuraHookFile

/// 被 Claude Code hook 呼叫。stdin 收 hook JSON，併進 `~/.agentaura/sessions/<id>.json`。
///
/// **任何失敗都必須靜默 exit 0**（Global Constraint）：這是觀測性程式，
/// 絕不可讓錯誤浮上 agent 的畫面或影響其行為。
/// 實證教訓（user CLAUDE.md #8）：收尾/觀測動作炸掉會殺掉同輪的保本工作。

func rootURL() -> URL {
    if let override = ProcessInfo.processInfo.environment["AGENTAURA_ROOT"], !override.isEmpty {
        return URL(fileURLWithPath: override)
    }
    return SnapshotIO.defaultRoot
}

func main() {
    // 1. 讀 stdin。讀不到就安靜結束。
    guard let data = try? FileHandle.standardInput.readToEnd(), !data.isEmpty else { return }

    // 2. 解析。畸形就安靜結束。
    guard let payload = HookPayload(data: data) else { return }

    // 2b. 這次呼叫來自哪個 agent（D-d／spec §4.1）。不匹配一律 `.claude`，
    //     絕不 throw、絕不寫 stdout／stderr（`AgentArgument.agent(from:)` 自己的契約）。
    let agent = AgentArgument.agent(from: CommandLine.arguments)

    // 3. 取父行程資訊 —— 父行程即呼叫此 hook 的 claude／codex 本體。
    //    若 Task 01 的 mechanisms.md 判定父行程是 shell 而非 claude，
    //    改為不寫 pid，改由 HookFileSource 走心跳 TTL 判活。
    //    F15（codex-support §4.7）：已證實 Codex 的 hook 父行程**不是**逐事件的短命
    //    shell，pid 在一個 session 內（第一個到最後一個事件）維持穩定，`getppid()`
    //    判活的前提對 Codex 成立。**範圍限定**：這個結論來自 5 個跑在 `codex exec`
    //    的 session，互動 TUI 的行程結構未量——TUI 有可能由常駐行程 fork 出 session，
    //    那樣父行程會跨 session 存活而讓判活失真。預寫的 fallback（若實機驗證發現如此）
    //    是 `--agent codex` 時不寫 pid、改由 `SessionEnd` 的 `terminated` 單獨判死——
    //    **這個 task 不實作 fallback**，只留下這個決策點供之後接手。
    let ppid = getppid()
    let started = SysctlLiveness().startTime(ofPID: ppid)

    // 4. merge-write。任何 IO 錯誤都吞掉。
    try? SnapshotIO.update(sessionID: payload.sessionID, root: rootURL()) { existing in
        MergeRules.merge(payload, into: existing,
                         pid: ppid, pidStartedAt: started, agent: agent, now: Date())
    }
}

main()
// 隱含 exit 0：沒有任何 exit(非零) 路徑，也不輸出 stdout / stderr。
