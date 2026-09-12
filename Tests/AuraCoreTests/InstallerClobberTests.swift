import Testing
import Foundation
import AuraCore
@testable import AuraHookFile

/// T03 G3：`installerRefusesToClobber`（spec §6.3）。兩條呼叫路徑各自斷言（S0-1(iii)）：
/// (a) `connect` 對普通檔案／實體目錄／有效掛載／external 且壞掉都不得毀掉既有內容；
/// (b) `disconnect` 對普通檔案／實體目錄必須拒絕；
/// (c) `replaceExternalMount` 在 translocated／`~/Downloads` 時也必須拒絕。
@Suite("Installer 拒絕覆寫（G3）")
struct InstallerClobberTests {

    // MARK: - (a) connect 對普通檔案／實體目錄

    @Test("(a) connect 對普通檔案必須 throw，且內容位元組完全不變（T01 必辦③斷言形狀）")
    func connectRefusesRegularFileAndContentUnchanged() throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        try FileManager.default.createDirectory(at: layout.claudeHome.appendingPathComponent("skills"),
                                                 withIntermediateDirectories: true)
        let target = layout.claudeHome.appendingPathComponent("skills/agentaura")
        try "使用者的內容，不得消失".write(to: target, atomically: true, encoding: .utf8)
        let before = ClobberAssertionShape.contentSnapshot(at: target)
        #expect(before != nil)

        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        #expect(throws: InstallerFailure.self) {
            try installer.connect(force: false, translocated: false, inDownloads: false)
        }
        #expect(ClobberAssertionShape.contentSnapshot(at: target) == before,
                "普通檔案的內容必須完全不變——connect() 絕不能碰到它")
        #expect(ClobberAssertionShape.entryKind(at: target) == .regularFile)
    }

    @Test("(a) connect 對實體目錄必須 throw，目錄完好")
    func connectRefusesRealDirectory() throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        let target = layout.claudeHome.appendingPathComponent("skills/agentaura")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try "別人的安裝".write(to: target.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)

        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        #expect(throws: InstallerFailure.self) {
            try installer.connect(force: false, translocated: false, inDownloads: false)
        }
        #expect(ClobberAssertionShape.entryKind(at: target) == .directory)
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("marker.txt").path))
    }

    /// 「有效掛載」（一個已完好連上、owner 為 external 的掛載）：affordance 是 `.none`
    /// （已接上），`connect()` 的早退（`.none` → 回傳既有 stamp）本身就是保護機制——
    /// 它完全不觸碰既有 symlink，不需要靠 throw 才算「沒有 clobber」。這裡直接斷言
    /// symlink 目標與內容都原封不動，涵蓋 G3(a) 的「有效掛載」子句。
    @Test("(a) connect 對一個已完好運作的 external 掛載不觸碰——affordance .none 的早退本身就是保護")
    func connectDoesNotTouchValidExternalMount() throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        // 另一份獨立、真的能跑的「外部」plugin（模擬開發者自己的 repo 掛載）。
        let external = try InstallerFixture.make()
        defer { external.cleanup() }

        try FileManager.default.createDirectory(at: layout.claudeHome.appendingPathComponent("skills"),
                                                 withIntermediateDirectories: true)
        let target = layout.claudeHome.appendingPathComponent("skills/agentaura")
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: external.bundlePlugin)

        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        let before = try FileManager.default.destinationOfSymbolicLink(atPath: target.path)

        let stamp = try installer.connect(force: false, translocated: false, inDownloads: false)
        #expect(!stamp.isEmpty)
        let after = try FileManager.default.destinationOfSymbolicLink(atPath: target.path)
        #expect(after == before, "已完好運作的 external 掛載不得被 connect() 換成 bundle 內建的那份")
    }

    @Test("(a) connect 對 external 且壞掉的掛載（owner 判定為 .external）必須 throw .externalMountNeedsChoice，不得靜默替換")
    func connectRefusesBrokenExternalMountWithoutForce() async throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        try FileManager.default.createDirectory(at: layout.claudeHome.appendingPathComponent("skills"),
                                                 withIntermediateDirectories: true)
        let target = layout.claudeHome.appendingPathComponent("skills/agentaura")
        // 自我迴圈 symlink（ELOOP）——resolveFailure ∈ {.loop, .permissionDenied, .other}
        // 且無法用 rawLinkTarget 正向命中 bundle 前綴時，owner 判定為 .external（r6①）。
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: target)

        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        let observed = installer.probe()
        let state = InstallState.from(observed, verification: .unknown)
        #expect(state.affordance == .replaceExternal, "前提：這個 fixture 必須落在 replaceExternal 那一格，否則這條測試沒測到 G3 要測的東西")

        #expect(throws: InstallerFailure.self) {
            try installer.connect(force: false, translocated: false, inDownloads: false)
        }
        // force: true（= replaceExternalMount）才允許替換——這條會真的 spawn（T10b：經過 SpawnGate）。
        let stamp = try await SpawnGate.shared.run {
            try installer.replaceExternalMount(translocated: false, inDownloads: false)
        }
        #expect(!stamp.isEmpty)
    }

    /// **mutation-observability 專用**：繞過步驟 0–1（affordance 路由），直接呼叫
    /// `performConnectSteps()`——這是唯一能讓「拿掉第 4 步寫入點型別檢查」這個 mutation
    /// 變成可觀察紅燈的路徑（S0-1(ii)：一般情境下 affordance 早已先擋住同樣的違規，
    /// 從 `connect()` 整體外部測不出「拿掉第 4 步會不會出事」）。
    @Test("(a) [第 4 步獨立護欄] performConnectSteps 對普通檔案必須 throw，內容位元組完全不變")
    func performConnectStepsGuardsWriteTargetDirectly() throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        try FileManager.default.createDirectory(at: layout.claudeHome.appendingPathComponent("skills"),
                                                 withIntermediateDirectories: true)
        let target = layout.claudeHome.appendingPathComponent("skills/agentaura")
        try "使用者的內容，不得消失".write(to: target, atomically: true, encoding: .utf8)
        let before = ClobberAssertionShape.contentSnapshot(at: target)

        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        #expect(throws: InstallerFailure.writeTargetOccupied) {
            try installer.performConnectSteps()
        }
        #expect(ClobberAssertionShape.contentSnapshot(at: target) == before)
        #expect(ClobberAssertionShape.entryKind(at: target) == .regularFile)
    }

    // MARK: - (b) disconnect 對普通檔案／實體目錄

    @Test("(b) disconnect 對普通檔案必須拒絕，內容不變")
    func disconnectRefusesRegularFile() throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        try FileManager.default.createDirectory(at: layout.claudeHome.appendingPathComponent("skills"),
                                                 withIntermediateDirectories: true)
        let target = layout.claudeHome.appendingPathComponent("skills/agentaura")
        try "使用者的內容".write(to: target, atomically: true, encoding: .utf8)
        let before = ClobberAssertionShape.contentSnapshot(at: target)

        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        #expect(throws: InstallerFailure.writeTargetOccupied) { try installer.disconnect() }
        #expect(ClobberAssertionShape.contentSnapshot(at: target) == before)
    }

    @Test("(b) disconnect 對實體目錄必須拒絕，目錄完好")
    func disconnectRefusesRealDirectory() throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        let target = layout.claudeHome.appendingPathComponent("skills/agentaura")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        #expect(throws: InstallerFailure.writeTargetOccupied) { try installer.disconnect() }
        #expect(ClobberAssertionShape.entryKind(at: target) == .directory)
    }

    // MARK: - (c) replaceExternalMount 在 translocated／~/Downloads 時也必須拒絕

    @Test("(c) replaceExternalMount(translocated: true) 拒絕，即使 force 語意上已經是 true")
    func replaceExternalMountRefusesTranslocated() throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        #expect(throws: InstallerFailure.mustMoveToApplications) {
            try installer.replaceExternalMount(translocated: true, inDownloads: false)
        }
    }

    @Test("(c) replaceExternalMount(inDownloads: true) 拒絕")
    func replaceExternalMountRefusesDownloads() throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        #expect(throws: InstallerFailure.mustMoveToApplications) {
            try installer.replaceExternalMount(translocated: false, inDownloads: true)
        }
    }
}
