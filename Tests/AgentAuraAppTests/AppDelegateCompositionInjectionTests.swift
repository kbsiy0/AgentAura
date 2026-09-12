import Testing
import Foundation
@testable import AgentAuraApp
import AuraCore
import AuraHookFile

/// `productionUsesRealInstaller`／`productionUsesRealLoginItem`／`verificationStoreIsInjected`
/// 的「生產注入」那半（spec §6.2；掃描那半已由 `HookVerificationStoreSourceScanTests`／T07 交付）。
///
/// `root`／`defaults`／`makeRenderer` 覆寫成安全值（temp 目錄／temp suite／`SpyRenderer`）——
/// 這條 gate 只驗證 `installer`／`makeLoginItem` **這兩個沒有被覆寫**時，生產預設值是真的
/// （不是 fake、不是指向 temp 的套套邏輯比對）。`installer.probe()`／`LoginItem` 建構本身
/// 只讀不寫（`lstat`／`SMAppService.mainApp` 在 `swift test` 執行環境下 `isSupported` 恆
/// false，短路跳過任何系統查詢），不違反「測試裡絕不碰真的 ~/.claude」——探測一個
/// 使用者機器上大概率存在、絕對不會被寫入的路徑，跟「碰」是兩回事。
@MainActor
@Suite("生產注入不是 fake（productionUsesRealInstaller／productionUsesRealLoginItem）", .serialized)
struct AppDelegateCompositionInjectionTests {

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-composition-injection-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func freshDefaults() throws -> (defaults: UserDefaults, suiteName: String) {
        let suite = "io.agentaura.tests.compositioninjection.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    @Test("productionUsesRealInstaller：預設 installer.claudeHome 以 /.claude 結尾，不含 temp 前綴")
    func productionUsesRealInstaller() {
        // 不需要 launch——installer 是 init 參數，建構完就在，且值就是「沒被覆寫的預設值」。
        let delegate = AppDelegate(root: FileManager.default.temporaryDirectory)
        let path = delegate.installer.claudeHome.path
        #expect(path.hasSuffix("/.claude"), "生產 claudeHome 應以 /.claude 結尾，實際 \(path)")
        #expect(!path.hasPrefix("/var/folders/"), """
            生產 claudeHome 不該落在 /var/folders/ 下（那是測試注入的 temp 值），實際 \(path)
            """)
        #expect(!path.hasPrefix(NSTemporaryDirectory()), """
            生產 claudeHome 不該落在 NSTemporaryDirectory() 下，實際 \(path)
            """)
    }

    @Test("productionUsesRealLoginItem：不覆寫 makeLoginItem 時，生產注入的是真的 LoginItem 型別，不是 FakeLoginItem")
    func productionUsesRealLoginItem() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let spy = SpyRenderer()
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   makeRenderer: { spy })   // installer／makeLoginItem 皆用生產預設值
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        #expect(delegate.loginItem is LoginItem, """
            生產注入的 loginItem 型別是 \(type(of: delegate.loginItem as Any))，不是真的 LoginItem——
            composition root 沒有接上生產實作
            """)
        #expect(!(delegate.loginItem is FakeLoginItem), "生產路徑不該注入 FakeLoginItem")
    }

    @Test("verificationStoreIsInjected（生產半）：launch 之後 verificationStore 真的被建構、不是 nil")
    func verificationStoreIsInjectedInProduction() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let spy = SpyRenderer()
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        #expect(delegate.verificationStore != nil, """
            applicationDidFinishLaunching 之後 verificationStore 仍是 nil——
            composition root 沒有真的建構 HookVerificationStore，probe() 的憑證比對永遠拿不到店
            """)
        // 真的是注入同一份 defaults 建的（不是憑空一個全新 store）——round-trip 一次。
        delegate.verificationStore.writeVerified("probe:stamp:1.0")
        #expect(HookVerificationStore(defaults: defaults).verification(for: "probe:stamp:1.0") == .verified, """
            delegate.verificationStore 寫入的憑證，用同一份 defaults 建的新 store 讀不到——
            代表 verificationStore 沒有真的用注入的 defaults 建構
            """)
    }
}
