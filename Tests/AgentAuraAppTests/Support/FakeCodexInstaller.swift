import Foundation

/// codex-support T01 佔位——對抗式 double `FakeCodexInstaller`（spec §6.1(7)、§8.1
/// file layout：`Tests/AgentAuraAppTests/Support/FakeCodexInstaller`）。供 T10 的
/// `CodexWiringSmokeTests`（CX24⑤）、`stalePathReconnectDisconnectsBeforeConnecting`
/// （CX35）、`codexReconnectNeverDisconnectsWhenPathIsRejected`（CX39）共用。
///
/// **T01b（review M2）**：協定簽章對齊 spec §4.4／§2 已定案的
/// `CodexInstaller.connect(json:translocated:inDownloads:) throws -> Data`／
/// `disconnect(ifContentsEqual:) throws`——舊版本地協定是零參數的 `connect()`／
/// `disconnect()`，**在原理上表達不出** CX39（「`translocated` 時 `connect` 被拒，
/// 所以 `disconnect` 呼叫次數必須是 0」）與 CX35／CX17（「內容不符就不刪」）這兩個
/// 情境——不是簽章微調，是少了承載這些情境的維度。與既有
/// `Tests/AgentAuraAppTests/Support/FakeLoginItem.swift` 在 `LoginItemControlling`
/// 落地前的做法不同：那時協定還沒定案；這裡 spec 早就寫死了，照抄零成本。
/// `probe()` 的回傳型別（`FakeCodexProbeState`）仍是暫定——`CodexInstaller.probe()`
/// 的正式回傳型別（`CodexObservation`，T04）落地後對齊即可。
protocol CodexInstallerProtocol {
    func probe() throws -> FakeCodexProbeState
    func connect(json: Data, translocated: Bool, inDownloads: Bool) throws -> Data
    func disconnect(ifContentsEqual: Data?) throws
}

enum FakeCodexProbeState: Equatable {
    case notConnected
    case connected(Data)
}

enum FakeCodexInstallerError: Error, Equatable {
    case probeFailed
    /// `connect` 因為 `translocated || inDownloads` 被拒（R-5／R-9；CX39 的情境）。
    case blockedByBundlePath
    /// `disconnect(ifContentsEqual:)` 給的內容與磁碟上的不符（CX35／CX17 的情境）。
    case contentsMismatch
}

/// 四種刁鑽行為，見 spec §6.1(7)：
/// ① `connect()` 成功但 `probe()` 仍回 `.notConnected`；
/// ② `disconnect()` 宣稱成功但檔案還在（`diskContents` 不清空）；
/// ③ `probe()` 丟錯；
/// ④ 記錄 `connect`／`disconnect`／`probe` 的呼叫順序與次數（`callOrder`，任何 mode 都記）。
///
/// 額外兩個維度（T01b M2，不分 mode、對所有 mode 一致生效，比照 spec §4.4 執行層的
/// 保本動作「不准只信路由層」）：
/// - `connect(translocated: true, ...)` 或 `inDownloads: true` 一律 throw
///   `.blockedByBundlePath`，不寫入、不改動 `diskContents`（CX39 用：驗證「被拒時
///   disconnect 呼叫次數是 0」，需要呼叫端因為 `connect` 真的丟錯而不往下呼叫 disconnect）。
/// - `disconnect(ifContentsEqual:)` 給的內容與 `diskContents` 不符時一律 throw
///   `.contentsMismatch`、不清空（CX35／CX17 用）。
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

    func connect(json: Data, translocated: Bool, inDownloads: Bool) throws -> Data {
        callOrder.append("connect")
        guard !translocated, !inDownloads else { throw FakeCodexInstallerError.blockedByBundlePath }
        if case .connectSucceedsButProbeStaysNotConnected = mode {
            // 假裝寫成功但不真的記錄進「磁碟」——probe() 之後仍會回 .notConnected，
            // 逼呼叫端不能只信 connect() 的回傳值。
            return json
        }
        diskContents = json
        return json
    }

    func disconnect(ifContentsEqual expected: Data?) throws {
        callOrder.append("disconnect")
        if let expected, expected != diskContents {
            throw FakeCodexInstallerError.contentsMismatch
        }
        if case .disconnectClaimsSuccessButLeavesFile = mode {
            return   // 宣稱成功（不 throw），但 diskContents 刻意不清空
        }
        diskContents = nil
    }
}
