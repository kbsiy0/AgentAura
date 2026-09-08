import Testing
import Foundation
@testable import AuraCore

@Suite("Liveness 與 pid 回收（§3.5）")
struct LivenessTests {

    @Test("能取得自己這個 process 的啟動時戳")
    func ownStartTime() {
        let probe = SysctlLiveness()
        let t = probe.startTime(ofPID: getpid())
        #expect(t != nil)
        #expect(t! > 1_600_000_000, "應是合理的 unix 秒數")
        #expect(t! <= Int64(Date().timeIntervalSince1970) + 1)
    }

    @Test("自己這個 process 用正確時戳查詢為活著")
    func selfIsAlive() {
        let probe = SysctlLiveness()
        let pid = getpid()
        let t = probe.startTime(ofPID: pid)!
        #expect(probe.isAlive(pid: pid, startedAt: t))
    }

    @Test("時戳不符即視為已死 —— 這就是 pid 回收的防線")
    func mismatchedStartTimeIsDead() {
        let probe = SysctlLiveness()
        let pid = getpid()
        let real = probe.startTime(ofPID: pid)!
        #expect(!probe.isAlive(pid: pid, startedAt: real + 1),
                "pid 相同但啟動時戳不同 → 是被回收後的另一個 process")
        #expect(!probe.isAlive(pid: pid, startedAt: 0))
    }

    @Test("不存在的 pid 回 nil / 已死")
    func nonexistentPID() {
        let probe = SysctlLiveness()
        // PID_MAX 之上必然不存在
        #expect(probe.startTime(ofPID: 999_999) == nil)
        #expect(!probe.isAlive(pid: 999_999, startedAt: 12345))
    }

    @Test("非法 pid 不得 crash")
    func invalidPIDs() {
        let probe = SysctlLiveness()
        for pid: Int32 in [0, -1, -999, Int32.max, Int32.min] {
            _ = probe.startTime(ofPID: pid)
            _ = probe.isAlive(pid: pid, startedAt: 1)
        }
    }

    @Test("真實子行程結束後即判定為死")
    func realChildProcessDies() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["30"]
        try p.run()
        let pid = p.processIdentifier
        let probe = SysctlLiveness()
        let t = try #require(probe.startTime(ofPID: pid))
        #expect(probe.isAlive(pid: pid, startedAt: t))

        p.terminate()
        p.waitUntilExit()
        // 收屍後 sysctl 應查不到
        #expect(!probe.isAlive(pid: pid, startedAt: t))
    }

    @Test("StubLiveness 可完全控制回答，供其他 suite 使用")
    func stubBehaviour() {
        let stub = StubLiveness(table: [100: 555])
        #expect(stub.isAlive(pid: 100, startedAt: 555))
        #expect(!stub.isAlive(pid: 100, startedAt: 556), "時戳不符 → 死")
        #expect(!stub.isAlive(pid: 101, startedAt: 555), "pid 不在表中 → 死")
    }
}
