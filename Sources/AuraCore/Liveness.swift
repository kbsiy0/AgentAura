import Foundation

public enum Liveness: Equatable, Sendable {
    case alive(pid: Int32)
    case ended
}

public protocol LivenessProbing: Sendable {
    /// 回傳該 pid 的啟動時戳（unix 秒）；查不到回 nil。
    func startTime(ofPID pid: Int32) -> Int64?
    /// pid **與**啟動時戳皆相符才算活著。
    func isAlive(pid: Int32, startedAt: Int64) -> Bool
}

extension LivenessProbing {
    public func isAlive(pid: Int32, startedAt: Int64) -> Bool {
        guard let t = startTime(ofPID: pid) else { return false }
        return t == startedAt
    }
}

/// 用 `sysctl(KERN_PROC_PID)` 取 `kinfo_proc.kp_proc.p_starttime`。
///
/// 只比 pid 不足以判定同一個 process —— pid 會被系統回收。時戳是識別碼的另一半。
public struct SysctlLiveness: LivenessProbing {
    public init() {}

    public func startTime(ofPID pid: Int32) -> Int64? {
        guard pid > 0 else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let rc = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        // process 不存在時 rc 可能是 0 但 size 歸零，必須一併檢查。
        guard rc == 0, size > 0, info.kp_proc.p_pid == pid else { return nil }
        return Int64(info.kp_proc.p_starttime.tv_sec)
    }
}

/// 測試與對抗式 double 用：完全可控的 liveness 回答。
///
/// E15（/simplify 波次2，struct#B1）：`internal` 而非 `public`——只有 `Tests/AuraCoreTests`
/// 用它（`@testable import AuraCore` 對 `internal` 一樣拿得到），生產 module 對外不該公開
/// 一個「完全可控」的測試替身讓任何 importer 都能建構。`AgentAuraAppTests` 沒有使用它。
struct StubLiveness: LivenessProbing {
    let table: [Int32: Int64]
    init(table: [Int32: Int64]) { self.table = table }
    func startTime(ofPID pid: Int32) -> Int64? { table[pid] }
}
