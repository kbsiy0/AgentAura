import Testing
import Foundation

/// codex-support T01 自我測試：`FakeCodexInstaller`／`FakeCodexStore` 真的有它們宣稱
/// 的行為——純記憶體邏輯，不依賴 T06／T10 的任何生產型別。**這些合理地是 GREEN**：
/// 驗的是 fake 自己，同 `Tests/AuraCoreTests/CodexFixtureSelfTests.swift` 的角色。
@Suite("Codex fake 自我驗證")
struct CodexDoubleSelfTests {

    @Test("FakeCodexStore：write／read／clear 的預設路徑（不注入 corruptOnRead）逐位元組往返")
    func fakeCodexStoreRoundTripsByDefault() {
        let store = FakeCodexStore()
        #expect(store.read() == nil)
        let bytes = Data("hello".utf8)
        store.write(bytes)
        #expect(store.read() == bytes)
        #expect(store.writeCallCount == 1)
        store.clear()
        #expect(store.read() == nil)
        #expect(store.clearCallCount == 1)
    }

    @Test("FakeCodexStore：corruptOnRead 設定後，讀回來的位元組與寫入的不同")
    func fakeCodexStoreCanSimulateRoundTripCorruption() {
        let store = FakeCodexStore()
        store.corruptOnRead = { data in data + Data([0xFF]) }
        let bytes = Data("hello".utf8)
        store.write(bytes)
        #expect(store.read() != bytes, "corruptOnRead 生效後，讀回來的應該與寫入的不同")
    }

    @Test("FakeCodexInstaller：呼叫序與次數逐一累計（四種 mode 共用同一套記帳）")
    func fakeCodexInstallerRecordsCallOrder() throws {
        let fake = FakeCodexInstaller(mode: .normal)
        _ = try fake.probe()
        _ = try fake.connect()
        try fake.disconnect()
        _ = try fake.probe()
        #expect(fake.callOrder == ["probe", "connect", "disconnect", "probe"])
        #expect(fake.probeCallCount == 2)
        #expect(fake.connectCallCount == 1)
        #expect(fake.disconnectCallCount == 1)
    }

    @Test("FakeCodexInstaller：① connect 成功但 probe 仍回 notConnected")
    func modeConnectSucceedsButProbeStaysNotConnected() throws {
        let fake = FakeCodexInstaller(mode: .connectSucceedsButProbeStaysNotConnected)
        _ = try fake.connect()
        #expect(try fake.probe() == .notConnected)
    }

    @Test("FakeCodexInstaller：② disconnect 宣稱成功但檔案還在")
    func modeDisconnectClaimsSuccessButLeavesFile() throws {
        let seeded = Data("already-there".utf8)
        let fake = FakeCodexInstaller(mode: .disconnectClaimsSuccessButLeavesFile, seededDiskContents: seeded)
        try fake.disconnect()   // 不 throw
        #expect(fake.diskContents == seeded, "宣稱斷開成功，但磁碟內容必須還在")
    }

    @Test("FakeCodexInstaller：③ probe 丟錯")
    func modeProbeThrows() {
        let fake = FakeCodexInstaller(mode: .probeThrows)
        #expect(throws: FakeCodexInstallerError.self) { _ = try fake.probe() }
    }

    @Test("FakeCodexInstaller：normal 模式下 connect 之後 probe 回 .connected 且位元組一致")
    func normalModeConnectThenProbeAgree() throws {
        let fake = FakeCodexInstaller(mode: .normal)
        let written = try fake.connect()
        #expect(try fake.probe() == .connected(written))
    }
}
