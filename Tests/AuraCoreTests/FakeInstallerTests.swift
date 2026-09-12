import Testing
import AuraCore

/// T01 對抗式 double 的自我測試：證明 `FakeInstaller` 的三個變體真的刁鑽
/// ——一個「相信 `connect()` 回傳值就算數」的天真呼叫端會被騙過，
/// 只有「connect 完再 probe 一次」才抓得到。**這條合理地是 GREEN**：
/// 驗的是 double 自己的行為，不是還沒寫的真 `Installer`。
@Suite("FakeInstaller 自我驗證")
struct FakeInstallerTests {

    @Test("① connect() 不 throw，但 probe() 之後仍是 notConnected —— 天真呼叫端會被騙過")
    func connectSucceedsButProbeStillNotConnected() throws {
        let fake = FakeInstaller(mode: .connectSucceedsButProbeStillNotConnected)
        try fake.connect(force: false, translocated: false, inDownloads: false)
        #expect(fake.connectCallCount == 1)

        // 天真的假設：「connect 沒丟錯 ⇒ 連上了」。
        let naiveAssumptionHolds = true
        #expect(naiveAssumptionHolds, "connect() 本身確實沒有 throw")

        // 但 spec §4.1 第 5 步要求的「connect 完再 probe 一次」會拆穿它：
        let observed = try fake.probe()
        #expect(observed.entryType == .absent, "probe() 之後仍是 notConnected（entryType == .absent）")
        #expect(InstallState.notConnected.affordance != .none,
                "notConnected 不該被誤判成已接上")
    }

    @Test("② probe 說 connected 但 exec 驗證應該失敗 —— connect() 必須 throw .hookBlockedOrBroken")
    func probeConnectedButExecVerificationFails() throws {
        let fake = FakeInstaller(mode: .probeConnectedButExecVerificationFails)
        let observed = try fake.probe()
        #expect(observed.hookBinaryExecutable == true, "看起來完好——access(X_OK) 不足以證明能跑")

        #expect(throws: InstallerError.hookBlockedOrBroken(.noArtifact)) {
            try fake.connect(force: false, translocated: false, inDownloads: false)
        }
    }

    @Test("③ spawn 本身丟錯 —— connect() 必須把它變成明確的錯誤，不是靜默吞掉")
    func spawnItselfThrows() throws {
        let fake = FakeInstaller(mode: .spawnItselfThrows)
        #expect(throws: InstallerError.spawnFailed) {
            try fake.connect(force: false, translocated: false, inDownloads: false)
        }
        #expect(fake.connectCallCount == 1, "呼叫必須真的發生過，不是被短路")
    }

    @Test("disconnect() 呼叫次數會被記錄，供之後守 disconnectDoesNotAcknowledge 一類的 gate")
    func disconnectCallCountIsTracked() throws {
        let fake = FakeInstaller(mode: .normal(LinkObservationFixtures.symlinkToThisAppComplete))
        try fake.disconnect()
        try fake.disconnect()
        #expect(fake.disconnectCallCount == 2)
    }
}
