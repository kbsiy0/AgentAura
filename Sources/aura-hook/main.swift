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

    // 3. 取父行程資訊 —— 父行程即呼叫此 hook 的 claude 本體。
    //    若 Task 01 的 mechanisms.md 判定父行程是 shell 而非 claude，
    //    改為不寫 pid，改由 HookFileSource 走心跳 TTL 判活。
    let ppid = getppid()
    let started = SysctlLiveness().startTime(ofPID: ppid)

    // 4. merge-write。任何 IO 錯誤都吞掉。
    try? SnapshotIO.update(sessionID: payload.sessionID, root: rootURL()) { existing in
        MergeRules.merge(payload, into: existing,
                         pid: ppid, pidStartedAt: started, now: Date())
    }
}

main()
// 隱含 exit 0：沒有任何 exit(非零) 路徑，也不輸出 stdout / stderr。
