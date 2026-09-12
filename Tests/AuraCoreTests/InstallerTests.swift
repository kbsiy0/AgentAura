import Testing
import Foundation
import AuraCore
@testable import AuraHookFile

/// T03 §4.1：`Installer` 的基本行為與 affordance 路由。G2（路徑範圍）與 G3（拒絕覆寫）
/// 另在 `InstallerPathScopeTests.swift`／`InstallerClobberTests.swift`；G4（exec 驗證）
/// 另在 `InstallerExecVerificationTests.swift`——都用同一份 `InstallerFixture`。
@Suite("Installer 基本行為與 affordance 路由")
struct InstallerTests {

    @Test("probe()：claudeHome 不存在 → claudeHomeExists == false")
    func probeReportsMissingClaudeHome() throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        try FileManager.default.removeItem(at: layout.claudeHome)
        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        #expect(installer.probe().claudeHomeExists == false)
    }

    @Test("probe()：全新 claudeHome、尚未接上 → entryType .absent")
    func probeReportsAbsentBeforeConnect() throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        let obs = installer.probe()
        #expect(obs.entryType == .absent)
        #expect(InstallState.from(obs, verification: .unknown) == .notConnected)
    }

    @Test("connect() 成功路徑：回傳 stamp，probe() 之後是 .connected(owner: .thisApp)")
    func connectSucceedsAndProbeReflectsConnected() async throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        // T08：全套件並行時真的 spawn 會跟其他測試搶資源，預設 2 秒偶發不夠（同 T06b 的教訓，
        // 這裡是被 T08 新增的一批也會 spawn 的測試放大了發生機率）。
        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin,
                                  verificationTimeout: 5)
        let stamp = try await SpawnGate.shared.run {
            try installer.connect(force: false, translocated: false, inDownloads: false)
        }
        #expect(!stamp.isEmpty)

        let after = installer.probe()
        #expect(InstallState.from(after, verification: .unknown) == .connected(owner: .thisApp, verified: .unknown))
        #expect(after.hookBinaryStamp == stamp, "回傳的 stamp 必須與 probe() 觀測到的一致，上層才寫得出正確憑證")
    }

    @Test("connect() 已經接上 → 冪等成功，回傳既有 stamp，不 throw（D-i：affordance .none）")
    func connectOnAlreadyConnectedIsIdempotent() async throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin,
                                  verificationTimeout: 5)   // T08：同上，並行 spawn 搶資源
        // 只有第一次真的 spawn（第二次早退成 .alreadyConnected），但兩次呼叫都經過 SpawnGate——
        // 早退那次瞬間完成，序列化成本可忽略。
        let first = try await SpawnGate.shared.run {
            try installer.connect(force: false, translocated: false, inDownloads: false)
        }
        let second = try await SpawnGate.shared.run {
            try installer.connect(force: false, translocated: false, inDownloads: false)
        }
        #expect(first == second)
    }

    @Test("disconnect() 移除掛載後 probe() 回到 .notConnected；~/.agentaura 與 app 不受影響（S1-A9，這裡連引用都沒有）")
    func disconnectRemovesLinkAndProbeReflectsNotConnected() async throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin,
                                  verificationTimeout: 5)   // T08：同上，並行 spawn 搶資源
        _ = try await SpawnGate.shared.run {
            try installer.connect(force: false, translocated: false, inDownloads: false)
        }
        try installer.disconnect()
        #expect(InstallState.from(installer.probe(), verification: .unknown) == .notConnected)
    }

    @Test("disconnect() 在 absent 上是冪等成功（沒什麼好斷開的）")
    func disconnectOnAbsentIsIdempotent() throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        try installer.disconnect()   // 不 throw 就是綠
    }

    @Test("connect(translocated: true) 一律拒絕，不管其餘狀態（S1-A4：App Translocation 會讓 symlink 指向會消失的臨時掛載）")
    func connectRejectsTranslocated() throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        #expect(throws: InstallerFailure.mustMoveToApplications) {
            try installer.connect(force: false, translocated: true, inDownloads: false)
        }
    }

    @Test("connect(inDownloads: true) 一律拒絕（S1-S3：~/Downloads 同理會消失）")
    func connectRejectsDownloads() throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        #expect(throws: InstallerFailure.mustMoveToApplications) {
            try installer.connect(force: false, translocated: false, inDownloads: true)
        }
    }

    @Test("claudeHome 不存在 → connect() 拒絕且不建立 ~/.claude（D-h：不得建立它）")
    func connectRefusesWhenClaudeHomeMissing() throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        try FileManager.default.removeItem(at: layout.claudeHome)
        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        #expect(throws: InstallerFailure.cannotConnect(nil)) {
            try installer.connect(force: false, translocated: false, inDownloads: false)
        }
        #expect(!FileManager.default.fileExists(atPath: layout.claudeHome.path),
                "connect() 不得順手建立 ~/.claude")
    }

    @Test("bundle plugin 目錄不存在 → connect() 拒絕（.bundleIncomplete）")
    func connectRefusesWhenBundleIncomplete() throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        try FileManager.default.removeItem(at: layout.bundlePlugin)
        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        #expect(throws: InstallerFailure.bundleIncomplete) {
            try installer.connect(force: false, translocated: false, inDownloads: false)
        }
    }

    @Test("replaceExternalMount 就是 connect(force: true, …)（N6）：對一個已完好連上 thisApp 的掛載仍是冪等成功")
    func replaceExternalMountIsForceConnect() async throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin,
                                  verificationTimeout: 5)   // T08：同上，並行 spawn 搶資源
        _ = try await SpawnGate.shared.run {
            try installer.connect(force: false, translocated: false, inDownloads: false)
        }
        let stamp = try await SpawnGate.shared.run {
            try installer.replaceExternalMount(translocated: false, inDownloads: false)
        }
        #expect(!stamp.isEmpty)
    }
}
