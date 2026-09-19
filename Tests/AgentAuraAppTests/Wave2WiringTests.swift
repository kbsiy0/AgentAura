import Testing
import Foundation
import SwiftUI
@testable import AgentAuraApp
import AuraCore
import AuraHookFile

/// /simplify 波次2：波次1在 `AuraCore` 建好的五個單一來源（`InstallState.owner`／`.isConnected`／
/// `PanelBanner.error(for:)`／`PanelModel.mountTargetNote`／`SessionSummary.text`）接上 app 層
/// 呼叫點之後的接線 mutation——只驗證「呼叫點真的呼叫到新 API」，不是巧合維持舊行為
/// （`SessionSummary.text` 全部消費點都住在 `AuraCore` 內部，`TooltipText`／`PanelViewModel`
/// 波次1就已經接上，app 層沒有第三份重寫，不需要新測試）。
@MainActor
@Suite("波次2接線：新 API 真的接上（不是巧合維持舊行為）", .serialized)
struct Wave2WiringTests {

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-wave2wiring-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func freshDefaults() throws -> (defaults: UserDefaults, suiteName: String) {
        let suite = "io.agentaura.tests.wave2wiring.\(UUID().uuidString)"
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

    /// B4：`AppDelegate+Verification.apply(obs:verification:)` 的 `externalTargetPath`
    /// 現在讀 `InstallState.owner`（AuraCore）——真的建兩份獨立 fixture、真的 symlink
    /// 指到「別人的」bundle plugin，讓 `owner` 真的算成 `.external`，而不是手動賦值
    /// `externalTargetPath` 繞過推導本身。
    @Test("owner 接線：真的 external 掛載 → externalTargetPath 讀 InstallState.owner 推導出來")
    func ownerWiringSetsExternalTargetPath() async throws {
        let thisApp = try AppInstallerFixture.make()
        defer { thisApp.cleanup() }
        let external = try AppInstallerFixture.make()
        defer { external.cleanup() }
        // claudeHome/skills/agentaura -> external 的 bundlePlugin（不是 thisApp 自己的）。
        let skills = thisApp.claudeHome.appendingPathComponent("skills")
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: skills.appendingPathComponent("agentaura"), withDestinationURL: external.bundlePlugin)
        let installer = AppInstallerFixture.installer(
            claudeHome: thisApp.claudeHome, bundlePluginURL: thisApp.bundlePlugin, verificationTimeout: 3)

        // 前提：這份 fixture 真的會被判成 external（不是本 App 自己的掛載）。
        let obs = installer.probe()
        guard case .connected(let owner, _) = InstallState.from(obs, verification: .unknown), owner == .external else {
            Issue.record("前提失敗：這份 fixture 應該 probe 成 connected(owner: .external, _)")
            return
        }
        // `realpath` 解析（`obs.displayTargetPath`）而不是自己 `resolvingSymlinksInPath()`——
        // 兩者對 `/tmp` 這類系統符號連結的解析深度不保證一致（`/var` vs `/private/var`）。
        let expected = try #require(obs.displayTargetPath)

        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let spy = SpyRenderer()
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   installer: installer, makeLoginItem: { FakeLoginItem() }, makeRenderer: { spy })
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        await SpawnGate.shared.run {
            delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
            await wait(upTo: 10) { delegate.verificationStore.inFlight == nil }
        }

        #expect(delegate.installState.owner == .external, "前提：installState.owner 應該是 .external")
        #expect(delegate.externalTargetPath == expected, """
            externalTargetPath 應該由 installState.owner（AuraCore）推導，實際 \
            \(String(describing: delegate.externalTargetPath))—— \
            如果這裡是 nil 或指向本 App 的 plugin，代表 apply(obs:verification:) 沒有真的讀 owner
            """)
    }

    /// B2／E8：`handleConnectFailure` 現在只保留「該不該寫驗證憑證鍵」，文案改讀 AuraCore
    /// 窮盡的 `PanelBanner.error(for:)`——用一個不寫任何憑證鍵的失敗種類（`.cannotConnect`，
    /// `claudeHome` 不存在時真的會被 `Installer.connect` 丟出來）驗證訊息真的來自那個窮盡表，
    /// 不是本地又留了一份手搓字面。
    @Test("PanelBanner.error(for:) 接線：cannotConnect 失敗的 banner 文案讀 AuraCore 的窮盡表")
    func handleConnectFailureUsesPanelBannerError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-wave2wiring-noclaudehome-\(UUID().uuidString)")
        // 走 fixture 工廠（T10b）而非裸建構——即使不存在的 claudeHome 不會走到 exec
        // 驗證，仍要遵守「唯一允許裸建構 Installer 的兩個檔案」這條 gate。
        let installer = AppInstallerFixture.installer(
            claudeHome: root.appendingPathComponent("claudeHome-missing"),
            bundlePluginURL: root.appendingPathComponent("bundle-missing"))
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let spy = SpyRenderer()
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   installer: installer, makeLoginItem: { FakeLoginItem() }, makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }
        #expect(delegate.installState == .claudeNotFound, "前提：不存在的 claudeHome 應該 probe 成 .claudeNotFound")

        delegate.performConnect(force: false)

        #expect(delegate.banner?.text == PanelBanner.error(for: .cannotConnect(nil), language: delegate.language).text, """
            banner 文案應該與 PanelBanner.error(for:) 這個窮盡表算出來的一致，實際 \
            \(String(describing: delegate.banner?.text))—— \
            如果 handleConnectFailure 又手搓了第二份文案，這裡會漂移而不自知
            """)
        #expect(delegate.banner?.text == InstallState.claudeNotFound.healthLabel(delegate.language),
                "與 healthLabel 是同一個 oracle，不應該各自維護一份")
    }

    /// B6：`OptionsSectionView` 展開時的「掛載目標」行改讀 `PanelModel.mountTargetNote`——
    /// 用 `dump(view.body)` 讀 SwiftUI 值型別樹裡的字面文字（不需要真的 NSWindow／渲染），
    /// 直接斷言畫出來的字串是 mountTargetNote 那句「現有掛載指向：」，不是舊版「目前指向：」。
    @Test("mountTargetNote 接線：Options 掛載目標行讀 PanelModel.mountTargetNote")
    func optionsSectionUsesMountTargetNote() throws {
        let connected = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                        install: .connected(owner: .external, verified: .verified), version: "1.0",
                                        optionsExpanded: true, launchAtLogin: nil,
                                        externalTargetPath: "/Users/dev/repo/plugin", banner: nil,
                                        systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese, codex: .unavailable, codexSnippet: nil)
        let note = try #require(connected.mountTargetNote, "前提：connected(.external) 應該有 mountTargetNote")

        var dumped = ""
        dump(OptionsSectionView(model: connected, onAction: { _ in }).body, to: &dumped)
        #expect(dumped.contains(note), """
            Options 展開時應該顯示 PanelModel.mountTargetNote 的原句「\(note)」，實際內容裡找不到—— \
            如果這裡又變回自己組字串，兩處措辭遲早會漂移（reuse#3,4／altitude#5）
            """)
        #expect(!dumped.contains("目前指向："), "不應該再出現舊版字面「目前指向：」")

        // 反例：broken(external) 時（`isConnected == false`）即使 externalTargetPath 存在，
        // 這一行也不該出現——沿用原本「只在真的 connected 時才顯示」的顯示條件。
        let brokenExternal = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                             install: .broken(.hookMissing, owner: .external), version: "1.0",
                                             optionsExpanded: true, launchAtLogin: nil,
                                             externalTargetPath: "/Users/dev/repo/plugin", banner: nil,
                                             systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese, codex: .unavailable, codexSnippet: nil)
        var dumpedBroken = ""
        dump(OptionsSectionView(model: brokenExternal, onAction: { _ in }).body, to: &dumpedBroken)
        #expect(!dumpedBroken.contains(note), """
            broken(external) 不是 connected，不該顯示掛載目標行——實際內容裡卻找到了「\(note)」
            """)
    }
}
