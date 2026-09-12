import Foundation
import AuraCore

// T01 佔位 —— 對抗式 double：`FakeInstaller`（spec §6.1、T01 必辦②的鄰居）。
//
// `InstallerProtocol` 是這裡先放的最小介面，讓 fake 有東西可以 conform；
// **T03 寫 `Sources/AuraHookFile/Installer.swift` 時若簽章不同，這個 protocol
// 與下面的 fake 都要跟著調整或刪除**——不保證與正式簽章逐字相同，
// 保的是「三種刁鑽失敗模式」這個測試意圖不因為簽章微調而流失。

protocol InstallerProtocol {
    func probe() throws -> LinkObservation
    func connect(force: Bool, translocated: Bool, inDownloads: Bool) throws
    func disconnect() throws
}

enum InstallerError: Error, Equatable {
    case mustMoveToApplications
    case cannotConnect(InstallState.Reason?)
    case externalMountNeedsChoice
    case bundleIncomplete
    case verificationFailed
    case hookBlockedOrBroken(HookFailureKind)
    case spawnFailed

    enum HookFailureKind: Equatable { case noArtifact, timedOut }
}

/// 三個刁鑽變體，見 spec §6.1：
/// ① `connect()` 成功但 `probe()` 仍回 `notConnected`（第 5 步的驗證要真的會擋）；
/// ② `probe` 說 `connected` 但 exec 驗證失敗（第 6 步要真的會擋）；
/// ③ spawn 本身丟錯（`Process.run()` throw）。
final class FakeInstaller: InstallerProtocol {
    enum Mode {
        case connectSucceedsButProbeStillNotConnected
        case probeConnectedButExecVerificationFails
        case spawnItselfThrows
        case normal(LinkObservation)
    }

    var mode: Mode
    private(set) var connectCallCount = 0
    private(set) var disconnectCallCount = 0
    private(set) var probeCallCount = 0

    init(mode: Mode) { self.mode = mode }

    func probe() throws -> LinkObservation {
        probeCallCount += 1
        switch mode {
        case .connectSucceedsButProbeStillNotConnected:
            // 呼叫端若天真地相信 connect() 的回傳值就代表成功，不會發現這裡；
            // spec §4.1 第 5 步「probe() 必須是 .connected，否則 throw」就是為了擋這個。
            return LinkObservationFixtures.notConnected
        case .probeConnectedButExecVerificationFails:
            // 看起來完好（entryType／hooksJSONExists／執行位都對），但 exec 會被殺——
            // 只有第 6 步真的 spawn 才驗得出來。
            return LinkObservationFixtures.symlinkHookExecutableButQuarantined
        case .spawnItselfThrows:
            return LinkObservationFixtures.symlinkToThisAppComplete
        case .normal(let obs):
            return obs
        }
    }

    func connect(force: Bool, translocated: Bool, inDownloads: Bool) throws {
        connectCallCount += 1
        switch mode {
        case .connectSucceedsButProbeStillNotConnected:
            return   // 假裝連上了；呼叫端必須自己再 probe 一次才會發現沒真的連上
        case .probeConnectedButExecVerificationFails:
            throw InstallerError.hookBlockedOrBroken(.noArtifact)
        case .spawnItselfThrows:
            throw InstallerError.spawnFailed   // 模擬 `Process.run()` 本身丟錯
        case .normal:
            return
        }
    }

    func disconnect() throws {
        disconnectCallCount += 1
    }
}
