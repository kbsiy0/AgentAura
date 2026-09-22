import Testing
import Foundation
@testable import AgentAuraApp
import AuraCore
import AuraHookFile

/// T24：`Uninstaller`——D-1「完整移除」的五個動作。`AppDelegatePanelActionsWiredTests+Uninstall`
/// 只驗接線（`.uninstall` 動作真的走到 `performUninstall()`）；這裡直接建構 `Uninstaller`
/// 本身，逐一驗證五個步驟＋冪等（D-6）＋順序（D-3）＋安全界線。
@MainActor
@Suite("Uninstaller（T24 D-1）", .serialized)
struct UninstallerTests {

    /// D-3 順序驗證用：`set(false)` 被呼叫的當下，`markerKey` 是否還在 defaults 裡
    /// （erasePersistentDomain 還沒跑的話應該還在）。
    final class OrderCheckingLoginItem: LoginItemControlling {
        var isSupported = true
        private(set) var isEnabled = false
        private(set) var setCallCount = 0
        let defaults: UserDefaults
        let markerKey: String
        private(set) var markerPresentWhenCalled: Bool?
        init(defaults: UserDefaults, markerKey: String) {
            self.defaults = defaults
            self.markerKey = markerKey
        }
        func set(_ on: Bool) throws {
            setCallCount += 1
            isEnabled = on
            markerPresentWhenCalled = defaults.object(forKey: markerKey) != nil
        }
    }

    /// CX26 順序驗證用：同 `OrderCheckingLoginItem` 的既有形狀——`disconnect` 被呼叫的
    /// 當下 `markerKey` 是否還在 defaults 裡（`erasePersistentDomain()` 還沒跑的話應該還在）。
    final class OrderCheckingCodexInstaller: CodexInstalling {
        let defaults: UserDefaults
        let markerKey: String
        private(set) var disconnectCallCount = 0
        private(set) var markerPresentWhenCalled: Bool?
        init(defaults: UserDefaults, markerKey: String) {
            self.defaults = defaults
            self.markerKey = markerKey
        }
        func probe() -> CodexObservation {
            CodexObservation(codexHomeIsDirectory: true, entryType: .absent, contents: nil, displayPath: nil)
        }
        func connect(json: Data, translocated: Bool, inDownloads: Bool) throws -> Data { json }
        func disconnect(ifContentsEqual: Data?) throws {
            disconnectCallCount += 1
            markerPresentWhenCalled = defaults.object(forKey: markerKey) != nil
        }
    }

    struct Rig {
        let layout: AppInstallerFixture.Layout
        let installer: Installer
        let loginItem: FakeLoginItem
        let defaults: UserDefaults
        let suite: String
        let stateHome: URL
        let stateDirectory: URL
        let recycler: FakeRecycler
        let terminator: FakeTerminator
        /// T10（D-n／CX26）：`Uninstaller` 現在多吃兩個 Codex 依賴——全記憶體 fake，
        /// 不落地任何檔案，同其餘欄位的既有理由（這條測試只驗 Claude 側五步＋順序，
        /// Codex 那一步的正確性由 `CodexWiringSmokeTests`／`CodexHookStoreTests` 各自守）。
        let codexInstaller: FakeCodexInstaller
        let codexStore: CodexHookStore
    }

    func makeRig(linked: Bool = true) throws -> Rig {
        let layout = try AppInstallerFixture.make()
        if linked { try AppInstallerFixture.linkDirectly(layout) }
        let installer = AppInstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        let suite = "io.agentaura.tests.uninstaller.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let stateHome = layout.root.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: stateHome, withIntermediateDirectories: true)
        let stateDirectory = stateHome.appendingPathComponent(".agentaura")
        try FileManager.default.createDirectory(at: stateDirectory.appendingPathComponent("sessions"),
                                                withIntermediateDirectories: true)
        return Rig(layout: layout, installer: installer, loginItem: FakeLoginItem(), defaults: defaults,
                  suite: suite, stateHome: stateHome, stateDirectory: stateDirectory,
                  recycler: FakeRecycler(), terminator: FakeTerminator(),
                  codexInstaller: FakeCodexInstaller(mode: .normal), codexStore: CodexHookStore(defaults: defaults))
    }

    func cleanup(_ rig: Rig) {
        rig.layout.cleanup()
        rig.defaults.removePersistentDomain(forName: rig.suite)
    }

    /// 有界等待（沿用 `CompositionSmokeTests.wait`／`HookVerificationStoreTests.wait` 的形狀）：
    /// `recycleBundleAndTerminate` 的 `Task { @MainActor in }` 落在下一個 run loop turn，
    /// 直接 `while` 在 mutation 下會變掛住而不是變紅，`Thread.sleep` 忙等會讓 MainActor
    /// 的 serial executor 一直被佔住、那個 Task 永遠排不進來——必須用 `await Task.sleep` 讓出。
    func wait(upTo seconds: TimeInterval, until cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if cond() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @Test("run()：五步依序發生——登入項目取消、掛載移除、狀態目錄清空、defaults domain 清空、terminate 被呼叫")
    func runPerformsAllFiveSteps() async throws {
        let rig = try makeRig()
        defer { cleanup(rig) }
        rig.defaults.set("x", forKey: "someKey")
        #expect(FileManager.default.fileExists(atPath: rig.layout.claudeHome.appendingPathComponent("skills/agentaura").path))

        Uninstaller(installer: rig.installer, loginItem: rig.loginItem, defaults: rig.defaults,
                   bundleIdentifier: rig.suite, stateDirectory: rig.stateDirectory, homeDirectory: rig.stateHome,
                   recycler: rig.recycler, bundleURL: URL(fileURLWithPath: "/tmp/fake.app"),
                   terminator: rig.terminator, language: .traditionalChinese, codexInstaller: rig.codexInstaller, codexStore: rig.codexStore).run()

        #expect(rig.loginItem.setCallCount == 1, "應該呼叫 loginItem.set(false) 一次")
        #expect(rig.loginItem.isEnabled == false)
        #expect(!FileManager.default.fileExists(atPath: rig.layout.claudeHome.appendingPathComponent("skills/agentaura").path),
                "掛載應該被移除")
        #expect(!FileManager.default.fileExists(atPath: rig.stateDirectory.path), "~/.agentaura 應該被清空")
        #expect(rig.defaults.object(forKey: "someKey") == nil, "persistent domain 應該整個清空")
        #expect(rig.recycler.recycledURLs == [URL(fileURLWithPath: "/tmp/fake.app")], "應該把 bundleURL 送進 recycler")
        await wait(upTo: 2) { rig.terminator.terminateImmediatelyCallCount == 1 }
        #expect(rig.terminator.terminateImmediatelyCallCount == 1, "最後應該終止")
    }

    @Test("D-3：loginItem.set(false) 在清 defaults 之前被呼叫")
    func loginItemUnregisteredBeforeDefaultsErased() throws {
        let rig = try makeRig()
        defer { cleanup(rig) }
        rig.defaults.set("x", forKey: "marker")
        let orderChecker = OrderCheckingLoginItem(defaults: rig.defaults, markerKey: "marker")

        Uninstaller(installer: rig.installer, loginItem: orderChecker, defaults: rig.defaults,
                   bundleIdentifier: rig.suite, stateDirectory: rig.stateDirectory, homeDirectory: rig.stateHome,
                   recycler: rig.recycler, bundleURL: nil, terminator: rig.terminator, language: .traditionalChinese, codexInstaller: rig.codexInstaller, codexStore: rig.codexStore).run()

        #expect(orderChecker.setCallCount == 1)
        #expect(orderChecker.markerPresentWhenCalled == true, """
            loginItem.set(false) 被呼叫的當下 marker 應該還在 defaults 裡——
            代表清 defaults 這步（D-3）發生在它之後，不是之前
            """)
    }

    /// CX26：`codexInstaller.disconnect(ifContentsEqual:)`（D-n）必須早於
    /// `erasePersistentDomain()`——比對用的內容住在 persistent domain 裡，順序反了
    /// 就永遠比不中，Codex 那份掛載完整移除會留殘留。
    @Test("CX26：codex disconnect 在清 defaults 之前被呼叫")
    func uninstallRemovesCodexBeforeErasingDefaults() throws {
        let rig = try makeRig()
        defer { cleanup(rig) }
        rig.defaults.set("x", forKey: "marker")
        let orderChecker = OrderCheckingCodexInstaller(defaults: rig.defaults, markerKey: "marker")

        Uninstaller(installer: rig.installer, loginItem: rig.loginItem, defaults: rig.defaults,
                   bundleIdentifier: rig.suite, stateDirectory: rig.stateDirectory, homeDirectory: rig.stateHome,
                   recycler: rig.recycler, bundleURL: nil, terminator: rig.terminator, language: .traditionalChinese,
                   codexInstaller: orderChecker, codexStore: rig.codexStore).run()

        #expect(orderChecker.disconnectCallCount == 1)
        #expect(orderChecker.markerPresentWhenCalled == true, """
            codexInstaller.disconnect(ifContentsEqual:) 被呼叫的當下 marker 應該還在 defaults 裡——
            代表這一步（D-n）發生在 erasePersistentDomain() 之前，不是之後
            """)
    }

    @Test("bundleIdentifier == nil（非真的 app bundle 執行）：defaults 完全不動")
    func skipsDefaultsErasureWhenBundleIdentifierNil() throws {
        let rig = try makeRig()
        defer { cleanup(rig) }
        rig.defaults.set("x", forKey: "someKey")

        Uninstaller(installer: rig.installer, loginItem: rig.loginItem, defaults: rig.defaults,
                   bundleIdentifier: nil, stateDirectory: rig.stateDirectory, homeDirectory: rig.stateHome,
                   recycler: rig.recycler, bundleURL: nil, terminator: rig.terminator, language: .traditionalChinese, codexInstaller: rig.codexInstaller, codexStore: rig.codexStore).run()

        #expect(rig.defaults.object(forKey: "someKey") as? String == "x", """
            bundleIdentifier 為 nil 時不該呼叫 removePersistentDomain——那會是清掉一個
            我們根本不確定是不是自己的 domain
            """)
        #expect(rig.terminator.terminateImmediatelyCallCount == 1, "即使跳過清 defaults，仍要終止")
    }

    @Test("bundleURL == nil：不呼叫 recycler，直接 terminate")
    func skipsRecycleWhenBundleURLNil() throws {
        let rig = try makeRig()
        defer { cleanup(rig) }

        Uninstaller(installer: rig.installer, loginItem: rig.loginItem, defaults: rig.defaults,
                   bundleIdentifier: rig.suite, stateDirectory: rig.stateDirectory, homeDirectory: rig.stateHome,
                   recycler: rig.recycler, bundleURL: nil, terminator: rig.terminator, language: .traditionalChinese, codexInstaller: rig.codexInstaller, codexStore: rig.codexStore).run()

        #expect(rig.recycler.recycledURLs.isEmpty, "bundleURL 為 nil 時不該呼叫 recycler")
        #expect(rig.terminator.terminateImmediatelyCallCount == 1)
    }

    @Test("terminate() 只在 recycle 的 completion 之後才被呼叫，不是發出去就終止")
    func terminatesOnlyAfterRecycleCompletion() async throws {
        let rig = try makeRig()
        defer { cleanup(rig) }
        rig.recycler.callsCompletionSynchronously = false

        Uninstaller(installer: rig.installer, loginItem: rig.loginItem, defaults: rig.defaults,
                   bundleIdentifier: rig.suite, stateDirectory: rig.stateDirectory, homeDirectory: rig.stateHome,
                   recycler: rig.recycler, bundleURL: URL(fileURLWithPath: "/tmp/fake.app"),
                   terminator: rig.terminator, language: .traditionalChinese, codexInstaller: rig.codexInstaller, codexStore: rig.codexStore).run()

        #expect(rig.recycler.recycledURLs.count == 1, "應該已經呼叫 recycler.recycle")
        #expect(rig.terminator.terminateImmediatelyCallCount == 0, """
            completion 還沒觸發時 terminate() 不該被呼叫——否則垃圾桶操作有沒有真的落地是未定義的
            """)

        rig.recycler.fireCompletion()
        await wait(upTo: 2) { rig.terminator.terminateImmediatelyCallCount == 1 }
        #expect(rig.terminator.terminateImmediatelyCallCount == 1, "completion 觸發之後 terminate() 應該被呼叫恰好一次")
    }

    /// T25：`recycler.recycle` 的 completion 曾經把 `Error?` 整個吞掉——這裡從
    /// `Uninstaller.run()` 整條路徑驗證：完成回報失敗時真的有東西被寫下來（不是只在
    /// `UninstallFailureLog` 單元測試裡驗證那個型別本身能動，還要驗證接線接上了）。
    @Test("recycle 失敗：completion 回報 error 時寫下失敗紀錄，仍然 terminate")
    func recycleFailureIsRecordedNotSwallowed() async throws {
        let rig = try makeRig()
        defer { cleanup(rig) }
        struct FakeRecycleError: Error, LocalizedError {
            var errorDescription: String? { "測試用假錯誤：磁碟空間不足" }
        }
        rig.recycler.completionError = FakeRecycleError()
        let bundleURL = URL(fileURLWithPath: "/tmp/fake.app")

        Uninstaller(installer: rig.installer, loginItem: rig.loginItem, defaults: rig.defaults,
                   bundleIdentifier: rig.suite, stateDirectory: rig.stateDirectory, homeDirectory: rig.stateHome,
                   recycler: rig.recycler, bundleURL: bundleURL, terminator: rig.terminator, language: .traditionalChinese, codexInstaller: rig.codexInstaller, codexStore: rig.codexStore).run()

        await wait(upTo: 2) { rig.terminator.terminateImmediatelyCallCount == 1 }
        #expect(rig.terminator.terminateImmediatelyCallCount == 1, "recycle 失敗不該卡住 terminate")

        let logURL = rig.stateHome.appendingPathComponent(UninstallFailureLog.filename)
        let content = try String(contentsOf: logURL, encoding: .utf8)
        #expect(content.contains(bundleURL.path), "失敗紀錄應該包含來源路徑")
        #expect(content.contains("測試用假錯誤"), "失敗紀錄應該包含錯誤描述")
    }

    /// 對照組：成功時完整移除不該留下任何殘留——這是「只在失敗時才寫檔」設計決定的
    /// 迴歸守衛，不是空氣測試。
    @Test("recycle 成功：不留下任何失敗紀錄檔")
    func recycleSuccessLeavesNoFailureLog() async throws {
        let rig = try makeRig()
        defer { cleanup(rig) }
        let bundleURL = URL(fileURLWithPath: "/tmp/fake.app")

        Uninstaller(installer: rig.installer, loginItem: rig.loginItem, defaults: rig.defaults,
                   bundleIdentifier: rig.suite, stateDirectory: rig.stateDirectory, homeDirectory: rig.stateHome,
                   recycler: rig.recycler, bundleURL: bundleURL, terminator: rig.terminator, language: .traditionalChinese, codexInstaller: rig.codexInstaller, codexStore: rig.codexStore).run()

        await wait(upTo: 2) { rig.terminator.terminateImmediatelyCallCount == 1 }
        let logURL = rig.stateHome.appendingPathComponent(UninstallFailureLog.filename)
        #expect(!FileManager.default.fileExists(atPath: logURL.path), "成功時完整移除不該留下任何殘留檔案")
    }

    @Test("D-6：跑第二次（掛載／狀態目錄／defaults 都已經清空）不得爆炸，仍然終止")
    func runTwiceIsIdempotent() throws {
        let rig = try makeRig()
        defer { cleanup(rig) }

        let uninstaller = Uninstaller(installer: rig.installer, loginItem: rig.loginItem, defaults: rig.defaults,
                                      bundleIdentifier: rig.suite, stateDirectory: rig.stateDirectory,
                                      homeDirectory: rig.stateHome, recycler: rig.recycler,
                                      bundleURL: nil, terminator: rig.terminator, language: .traditionalChinese, codexInstaller: rig.codexInstaller, codexStore: rig.codexStore)
        uninstaller.run()
        uninstaller.run()   // 全部東西都已經不在了

        #expect(rig.terminator.terminateImmediatelyCallCount == 2, "第二次仍應該把 terminate 呼叫一次，不能因為前面都沒東西可清就整個早退")
    }
}
