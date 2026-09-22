import Testing
import Foundation
@testable import AgentAuraApp
import AuraCore
import AuraHookFile

/// `blockedSurvivesReprobeAndRestart`／`launchVerifiesUnlessAlreadyVerified`（spec §6.2）。
@MainActor
@Suite("啟動背景驗證的生命週期", .serialized)
struct AppDelegateVerificationLifecycleTests {

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-verifylifecycle-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func freshDefaults() throws -> (defaults: UserDefaults, suiteName: String) {
        let suite = "io.agentaura.tests.verifylifecycle.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    @MainActor
    func wait(upTo seconds: TimeInterval, until cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if cond() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// exec 驗證失敗（寫入 blocked 憑證）之後：(a) 接下來的 probe 不得把狀態變回 connected；
    /// (b) 用新的 AppDelegate ＋同一份 defaults 重建一次（模擬重啟）仍是 hookBlockedOrBroken。
    @Test("hookBlockedOrBroken 跨 onOpen 重新 probe 與跨重啟存活")
    func blockedSurvivesReprobeAndRestart() async throws {
        let layout = try AppInstallerFixture.makeWithSilentHookBinary()
        defer { layout.cleanup() }
        try AppInstallerFixture.linkDirectly(layout)
        let installer = AppInstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin,
                                  verificationTimeout: 3)
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let spy = SpyRenderer()
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   installer: installer, makeLoginItem: { FakeLoginItem() },
                                   confirmDisconnectCodex: { _, onConfirm in onConfirm() }, codexDependencies: .inert(), makeRenderer: { spy })
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        // T10b：觸發＋輪詢整段一起經過 SpawnGate——只 wrap 觸發那一下不夠，實際 spawn
        // 發生在啟動時派出去的背景驗證裡，鎖必須撐到輪詢等到結果才能放。
        await SpawnGate.shared.run {
            delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
            await wait(upTo: 10) {
                if case .broken(.hookBlockedOrBroken, _) = delegate.installState { return true }
                return false
            }
        }
        guard case .broken(.hookBlockedOrBroken, let owner1) = delegate.installState else {
            Issue.record("啟動背景驗證後應該是 broken(.hookBlockedOrBroken, _)，實際 \(delegate.installState)")
            return
        }
        #expect(owner1 == .thisApp)

        // (a) 再 probe 一次（模擬 onOpen）——不得回復成 connected。
        let onOpen = try #require(spy.onOpen)
        onOpen()
        guard case .broken(.hookBlockedOrBroken, _) = delegate.installState else {
            Issue.record("onOpen 重新 probe 之後不該回到 connected，實際 \(delegate.installState)")
            return
        }

        // (b) 用同一份 defaults 重建一次 AppDelegate，模擬重啟。
        let spy2 = SpyRenderer()
        let delegate2 = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                    installer: installer, makeLoginItem: { FakeLoginItem() },
                                    confirmDisconnectCodex: { _, onConfirm in onConfirm() }, codexDependencies: .inert(), makeRenderer: { spy2 })
        delegate2.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate2.applicationWillTerminate(Notification(name: .init("test"))) }
        guard case .broken(.hookBlockedOrBroken, _) = delegate2.installState else {
            Issue.record("「重啟」後（同一份 defaults）應該立刻是 broken(.hookBlockedOrBroken, _)，實際 \(delegate2.installState)")
            return
        }
    }

    /// `.unknown` 與 `.blocked` 各跑一次；`.verified` 不跑；`onOpen` 一次都不跑。
    @Test("verification == .unknown（從沒驗過）→ 啟動時跑一次，最終變成 blocked（實際 exec 過的證據）")
    func unknownTriggersVerificationAtLaunch() async throws {
        let layout = try AppInstallerFixture.makeWithSilentHookBinary()
        defer { layout.cleanup() }
        try AppInstallerFixture.linkDirectly(layout)
        let installer = AppInstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin,
                                  verificationTimeout: 3)
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let spy = SpyRenderer()
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   installer: installer, makeLoginItem: { FakeLoginItem() },
                                   confirmDisconnectCodex: { _, onConfirm in onConfirm() }, codexDependencies: .inert(), makeRenderer: { spy })
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        await SpawnGate.shared.run {
            delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
            await wait(upTo: 10) {
                if case .broken(.hookBlockedOrBroken, _) = delegate.installState { return true }
                return false
            }
        }
        guard case .broken(.hookBlockedOrBroken, _) = delegate.installState else {
            Issue.record(".unknown 應該在啟動時觸發驗證並最終變成 blocked，實際 \(delegate.installState)")
            return
        }
    }

    /// `.blocked`（之前失敗過，但現在已經修好）也要跑——R2：不跑的話使用者修好之後重開 app，
    /// chip 仍會永久說「macOS 擋住了 hook」。
    @Test("verification == .blocked（先前失敗過，現在已修好）→ 啟動時仍會重驗，成功後變 verified")
    func blockedRevalidatesAtLaunchAndCanSelfHeal() async throws {
        let layout = try AppInstallerFixture.make()   // 這次是真的會成功的二進位
        defer { layout.cleanup() }
        try AppInstallerFixture.linkDirectly(layout)
        let installer = AppInstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin,
                                  verificationTimeout: 3)
        let stamp = try #require(installer.probe().hookBinaryStamp, "前提：fixture 建好之後 probe 應該拿得到 stamp")

        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        // 預先寫入「先前失敗過」的憑證——模擬使用者上次啟動時 exec 被擋、現在已經修好
        // （例如使用者把 App 搬進了「應用程式」）。
        let preSeededStore = HookVerificationStore(defaults: defaults)
        preSeededStore.writeBlocked(stamp)
        #expect(preSeededStore.verification(for: stamp) == .blocked, "前提：預先寫入的憑證應該讀回 .blocked")

        let spy = SpyRenderer()
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   installer: installer, makeLoginItem: { FakeLoginItem() },
                                   confirmDisconnectCodex: { _, onConfirm in onConfirm() }, codexDependencies: .inert(), makeRenderer: { spy })
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        await SpawnGate.shared.run {
            delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
            await wait(upTo: 10) {
                if case .connected(_, .verified) = delegate.installState { return true }
                return false
            }
        }
        guard case .connected(_, .verified) = delegate.installState else {
            Issue.record(".blocked 應該在啟動時重驗，成功後自癒成 connected(_, verified: .verified)，實際 \(delegate.installState)")
            return
        }
    }

    /// S1-5（PARTIAL 殘餘一半，T13 收尾）：`AppDelegate+Verification.swift` 的 `.verified`
    /// case 先前只呼叫 `apply(obs:verification:)`，不碰 `banner`——使用者「再檢查一次」
    /// （或啟動時的背景驗證）修好之後，先前失敗留下的紅色「macOS 擋住了 hook」banner
    /// 還留在原地，跟已經翻綠的 chip 互相矛盾。與 `blockedRevalidatesAtLaunchAndCanSelfHeal`
    /// 同一個 fixture 形狀（先寫入 `.blocked` 憑證、給一個會成功的二進位、驗證自癒），
    /// 差別只多了「啟動前先塞一條舊的 `.error` banner」。
    @Test("驗證變成 .verified 時清掉既有的 .error banner")
    func verificationSuccessClearsStaleErrorBanner() async throws {
        let layout = try AppInstallerFixture.make()   // 會成功的二進位
        defer { layout.cleanup() }
        try AppInstallerFixture.linkDirectly(layout)
        let installer = AppInstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin,
                                  verificationTimeout: 3)
        let stamp = try #require(installer.probe().hookBinaryStamp, "前提：fixture 建好之後 probe 應該拿得到 stamp")

        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preSeededStore = HookVerificationStore(defaults: defaults)
        preSeededStore.writeBlocked(stamp)

        let spy = SpyRenderer()
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   installer: installer, makeLoginItem: { FakeLoginItem() },
                                   confirmDisconnectCodex: { _, onConfirm in onConfirm() }, codexDependencies: .inert(), makeRenderer: { spy })
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }
        // 模擬「先前按接上失敗過」留下的錯誤 banner。
        delegate.banner = .error(InstallState.hookBlockedPrescription(.english))

        await SpawnGate.shared.run {
            delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
            await wait(upTo: 10) {
                if case .connected(_, .verified) = delegate.installState { return true }
                return false
            }
        }
        guard case .connected(_, .verified) = delegate.installState else {
            Issue.record("前提失敗：應該自癒成 connected(_, verified: .verified)，實際 \(delegate.installState)")
            return
        }
        #expect(delegate.banner == nil, """
            驗證成功之後應該清掉舊的 .error banner，實際 \(String(describing: delegate.banner))——
            使用者會看到已經翻綠的健康 chip 旁邊還留著一條矛盾的紅色錯誤訊息（S1-5）
            """)
    }

    /// `.verified` 不跑：預先寫入正確憑證，注入一個「跑了就會失敗」的二進位——
    /// 若啟動驗證誤跑，`.verified` 會被錯誤地覆寫成 `.blocked`；若正確跳過，狀態應保持
    /// `.connected(_, verified: .verified)` 不變。這是比「數呼叫次數」更有牙齒的觀察方式
    /// （直接看副作用有沒有發生，不依賴額外 instrumentation）。
    ///
    /// **T10b：刻意不經過 SpawnGate**——這條測的是「正確行為下不 spawn」，固定睡 1.5 秒
    /// 只是給「萬一真的誤跑」留反應時間，不是在等一個已知會發生的 spawn。正常（無 bug）
    /// 情況下這裡完全不 spawn；把它包進閘門只會讓全套件白白多鎖 1.5 秒，沒有任何保護效果。
    @Test("verification == .verified → 啟動時不重驗（誤驗的話會被壞掉的二進位覆寫成 blocked）")
    func verifiedSkipsLaunchVerification() async throws {
        let layout = try AppInstallerFixture.makeWithSilentHookBinary()   // 一跑就會失敗
        defer { layout.cleanup() }
        try AppInstallerFixture.linkDirectly(layout)
        let installer = AppInstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin,
                                  verificationTimeout: 3)
        let stamp = try #require(installer.probe().hookBinaryStamp)

        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        HookVerificationStore(defaults: defaults).writeVerified(stamp)

        let spy = SpyRenderer()
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   installer: installer, makeLoginItem: { FakeLoginItem() },
                                   confirmDisconnectCodex: { _, onConfirm in onConfirm() }, codexDependencies: .inert(), makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        // 給背景驗證足夠時間「如果真的誤跑」會跑完並寫壞狀態；然後斷言狀態仍然乾淨。
        try await Task.sleep(nanoseconds: 1_500_000_000)
        guard case .connected(_, .verified) = delegate.installState else {
            Issue.record("""
                已經 .verified 的狀態不該在啟動時被重新驗證，實際 \(delegate.installState)——
                如果這裡變成 broken(.hookBlockedOrBroken, _)，代表 launchVerificationIfNeeded
                誤判成需要重驗，拿一顆會失敗的二進位去跑，把原本正確的 .verified 覆寫掉了
                """)
            return
        }
    }
}
