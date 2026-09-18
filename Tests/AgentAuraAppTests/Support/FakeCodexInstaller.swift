import Foundation

/// codex-support T01 佔位——對抗式 double `FakeCodexInstaller`（spec §6.1(7)、§8.1
/// file layout：`Tests/AgentAuraAppTests/Support/FakeCodexInstaller`）。供 T10 的
/// `CodexWiringSmokeTests`（CX24⑤）、`stalePathReconnectDisconnectsBeforeConnecting`
/// （CX35）、`codexReconnectNeverDisconnectsWhenPathIsRejected`（CX39）共用。
///
/// 本地的 `CodexInstallerProtocol`／`FakeCodexProbeState`／`FakeCodexInstallerError` 是
/// **暫定形狀**——跟既有 `Tests/AgentAuraAppTests/Support/FakeLoginItem.swift` 在
/// `LoginItemControlling` 落地前的做法同一套（見該檔開頭註解的「T01 的本地重製」）：
/// `Sources/AuraHookFile/CodexInstaller.swift`（T06）／`AppDelegate+Codex.swift`（T10）
/// 落地後，若composition root 需要的介面與這裡不同，把這裡對齊真型別即可，
/// 保的是「四種刁鑽行為＋呼叫序記錄」這個測試意圖不因簽章微調而流失。
protocol CodexInstallerProtocol {
    func probe() throws -> FakeCodexProbeState
    func connect() throws -> Data
    func disconnect() throws
}

enum FakeCodexProbeState: Equatable {
    case notConnected
    case connected(Data)
}

enum FakeCodexInstallerError: Error, Equatable {
    case probeFailed
}

/// 四種刁鑽行為，見 spec §6.1(7)：
/// ① `connect()` 成功但 `probe()` 仍回 `.notConnected`；
/// ② `disconnect()` 宣稱成功但檔案還在（`diskContents` 不清空）；
/// ③ `probe()` 丟錯；
/// ④ 記錄 `connect`／`disconnect`／`probe` 的呼叫順序與次數（`callOrder`，任何 mode 都記）。
final class FakeCodexInstaller: CodexInstallerProtocol {
    enum Mode {
        case connectSucceedsButProbeStaysNotConnected
        case disconnectClaimsSuccessButLeavesFile
        case probeThrows
        case normal
    }

    let mode: Mode
    /// fake 自己的「磁碟」——② 用它證明「宣稱斷開之後，檔案其實還在」。
    private(set) var diskContents: Data?
    private(set) var callOrder: [String] = []

    var connectCallCount: Int { callOrder.filter { $0 == "connect" }.count }
    var disconnectCallCount: Int { callOrder.filter { $0 == "disconnect" }.count }
    var probeCallCount: Int { callOrder.filter { $0 == "probe" }.count }

    init(mode: Mode, seededDiskContents: Data? = nil) {
        self.mode = mode
        self.diskContents = seededDiskContents
    }

    func probe() throws -> FakeCodexProbeState {
        callOrder.append("probe")
        if case .probeThrows = mode { throw FakeCodexInstallerError.probeFailed }
        if case .connectSucceedsButProbeStaysNotConnected = mode { return .notConnected }
        guard let d = diskContents else { return .notConnected }
        return .connected(d)
    }

    func connect() throws -> Data {
        callOrder.append("connect")
        let bytes = Data("fake-codex-hooks-json-\(UUID().uuidString)".utf8)
        if case .connectSucceedsButProbeStaysNotConnected = mode {
            // 假裝寫成功但不真的記錄進「磁碟」——probe() 之後仍會回 .notConnected，
            // 逼呼叫端不能只信 connect() 的回傳值。
            return bytes
        }
        diskContents = bytes
        return bytes
    }

    func disconnect() throws {
        callOrder.append("disconnect")
        if case .disconnectClaimsSuccessButLeavesFile = mode {
            return   // 宣稱成功（不 throw），但 diskContents 刻意不清空
        }
        diskContents = nil
    }
}
