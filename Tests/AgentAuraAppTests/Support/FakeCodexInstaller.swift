import Foundation
import AuraCore
@testable import AgentAuraApp

/// codex-support T01 佔位——對抗式 double `FakeCodexInstaller`（spec §6.1(7)、§8.1
/// file layout：`Tests/AgentAuraAppTests/Support/FakeCodexInstaller`）。供 T10 的
/// `CodexWiringSmokeTests`（CX24⑤）、`stalePathReconnectDisconnectsBeforeConnecting`
/// （CX35）、`codexReconnectNeverDisconnectsWhenPathIsRejected`（CX39）共用。
///
/// **T10（對齊 T04／T06 已落地的正式簽章）**：直接遵守 `CodexInstalling`
/// （`AppDelegate+Codex.swift`，composition root 用它注入替身）——`probe()` 不 throw、
/// 回真的 `CodexObservation`（T04），不再是 T01 當時暫定的本地協定 ＋
/// `FakeCodexProbeState`（doc comment 早已預告「落地後對齊即可」）。`connect`／
/// `disconnect` 簽章原本就已對齊 spec §4.4／§2，不動。
enum FakeCodexInstallerError: Error, Equatable {
    /// `connect` 因為 `translocated || inDownloads` 被拒（R-5／R-9；CX39 的情境）。
    case blockedByBundlePath
    /// `disconnect(ifContentsEqual:)` 給的內容與磁碟上的不符（CX35／CX17 的情境）。
    case contentsMismatch
}

/// 四種刁鑽行為，見 spec §6.1(7)：
/// ① `connect()` 成功但 `probe()` 仍回「未接上」形狀；
/// ② `disconnect()` 宣稱成功但檔案還在（`diskContents` 不清空）；
/// ③ `probe()` 回「不可用」形狀——同 `CodexInstaller.probe()` 的真實契約：對檔案系統的
///   失敗一律吞成 `.absent`／`codexHomeIsDirectory: false` 形狀，**不 throw**（T10 對齊，
///   舊版 `.probeThrows` 是 T01 暫定協定底下的近似，那個近似已經不成立）；
/// ④ 記錄 `connect`／`disconnect`／`probe` 的呼叫順序與次數（`callOrder`，任何 mode 都記）。
///
/// 額外兩個維度（T01b M2，不分 mode、對所有 mode 一致生效，比照 spec §4.4 執行層的
/// 保本動作「不准只信路由層」）：
/// - `connect(translocated: true, ...)` 或 `inDownloads: true` 一律 throw
///   `.blockedByBundlePath`，不寫入、不改動 `diskContents`（CX39 用：驗證「被拒時
///   disconnect 呼叫次數是 0」，需要呼叫端因為 `connect` 真的丟錯而不往下呼叫 disconnect）。
/// - `disconnect(ifContentsEqual:)`：磁碟為 nil（absent）一律冪等成功（同
///   `CodexInstaller.disconnect` 的 `ENOENT` 分支）；磁碟非 nil 時，`expected` 為 nil
///   或與磁碟不符一律 throw `.contentsMismatch`、不清空（CX35／CX17 用；同真實實作
///   「`expected == nil` 一律當作不符，`absent` 除外」的既有理由）。
final class FakeCodexInstaller: CodexInstalling {
    enum Mode {
        case connectSucceedsButProbeStaysNotConnected
        case disconnectClaimsSuccessButLeavesFile
        case probeReturnsUnavailable
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

    func probe() -> CodexObservation {
        callOrder.append("probe")
        if case .probeReturnsUnavailable = mode {
            return CodexObservation(codexHomeIsDirectory: false, entryType: .absent, contents: nil, displayPath: nil)
        }
        if case .connectSucceedsButProbeStaysNotConnected = mode {
            return CodexObservation(codexHomeIsDirectory: true, entryType: .absent, contents: nil, displayPath: nil)
        }
        guard let d = diskContents else {
            return CodexObservation(codexHomeIsDirectory: true, entryType: .absent, contents: nil, displayPath: nil)
        }
        return CodexObservation(codexHomeIsDirectory: true, entryType: .regularFile, contents: d,
                                displayPath: "/fake/.codex/hooks.json")
    }

    func connect(json: Data, translocated: Bool, inDownloads: Bool) throws -> Data {
        callOrder.append("connect")
        guard !translocated, !inDownloads else { throw FakeCodexInstallerError.blockedByBundlePath }
        if case .connectSucceedsButProbeStaysNotConnected = mode {
            // 假裝寫成功但不真的記錄進「磁碟」——probe() 之後仍回「未接上」形狀，
            // 逼呼叫端不能只信 connect() 的回傳值。
            return json
        }
        diskContents = json
        return json
    }

    func disconnect(ifContentsEqual expected: Data?) throws {
        callOrder.append("disconnect")
        guard let disk = diskContents else { return }   // absent：冪等成功（同真實 ENOENT 分支）
        guard let expected, expected == disk else {
            throw FakeCodexInstallerError.contentsMismatch
        }
        if case .disconnectClaimsSuccessButLeavesFile = mode {
            return   // 宣稱成功（不 throw），但 diskContents 刻意不清空
        }
        diskContents = nil
    }
}
