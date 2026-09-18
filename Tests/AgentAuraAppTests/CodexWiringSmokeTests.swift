import Testing
import Foundation
@testable import AgentAuraApp
import AuraCore
import AuraHookFile

/// codex-support T01 骨架（CX24，**T10 解除**）：composition-root smoke 五段
/// （spec §6.2／§6.3）——驗 `AppDelegate+Codex.swift`（T10）真的把 `CodexInstaller`／
/// `CodexHookStore`／`reprobeCodex()` 接起來，而不是「單元測試證明能用、composition
/// root 忘了傳」（user-level CLAUDE.md「Tested-capability ≠ wired-capability」）。
///
/// **五段**（CX24）：
/// ① 接線：`delegate` 真的持有注入的 codex 依賴，不是 nil／換成生產預設值。
/// ② fake 收到 `connect()` 呼叫：送出接上動作之後，fake 的呼叫序裡有一次 "connect"。
/// ③ 憑證取回是同一串位元組：`connect()` 回傳的 `Data` 與 `CodexHookStore` 讀回來的
///    **逐位元組**相等——不是「非 nil」，這正是「tested-capability ≠ wired-capability」
///    的反例（round-trip 若被悄悄改過，這一段才抓得到，②只證明呼叫發生了）。
/// ④ banner 含兩個關鍵詞（下一個 session 起生效／需要在 Codex 裡按同意，D-m）：
///    從 `L10nCodex` 的鍵推導，不寫死中文全文，語言一換也要能跟著換。
/// ⑤ spy 記 `probe()` 次數：`onOpen` 之後 `probeCallCount` 必須比呼叫前更多
///    （`reprobeCodex()` 四個時機之一；漏接的症狀是「裝了 Codex、開面板、什麼都沒有，
///    重開才出現」，見 spec §4.6）。
///
/// **型別依賴（RED 理由＝編譯依賴）**：`AppDelegate` 目前的 init 沒有任何 Codex 相關
/// 參數（T10 才加），`reprobeCodex()`／`performConnectCodex()`／`codexHookStore`／
/// `L10nCodex` 都還不存在。下面的注入參數名與呼叫序是**依 spec §4.6／§6.2／既有
/// `AppDelegateOnOpenTests.swift` 的注入模式推測的形狀**，不保證與 T10 最終簽章逐字
/// 相同——T10 若簽章不同，把對應呼叫調整即可，五段各自要驗的性質不變。
///
/// **T10 解除方式**：把測試函式裡的 `#if AURA_CODEX_PENDING_T10` / `#else` /
/// `Issue.record(...)` / `#endif` 拿掉，只留 `#if` 分支內的真斷言（依實際簽章調整）。
@MainActor
@Suite("Codex composition-root smoke（CX24）", .serialized)
struct CodexWiringSmokeTests {

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-codex-smoke-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func freshDefaults() throws -> (defaults: UserDefaults, suiteName: String) {
        let suite = "io.agentaura.tests.codexsmoke.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    @Test("五段：接線／fake 收到 connect／憑證位元組相等／banner 兩個關鍵詞／probe 次數增加")
    func codexConnectChainIsWired() throws {
        #if AURA_CODEX_PENDING_T10
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let spy = SpyRenderer()
        let fakeInstaller = FakeCodexInstaller(mode: .normal)

        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   makeRenderer: { spy }, codexInstaller: fakeInstaller)
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        // ① 接線：注入的依賴真的被持有，不是 nil／換成生產預設值。
        #expect(delegate.codexInstaller is FakeCodexInstaller,
                "composition root 沒有把注入的 fake 接上，實際型別 \(type(of: delegate.codexInstaller as Any))")

        // ② fake 收到 connect() 呼叫。
        delegate.performConnectCodex()
        #expect(fakeInstaller.connectCallCount == 1, "送出接上動作之後，fake 應該收到恰一次 connect()")

        // ③ 憑證取回是同一串位元組（不是「非 nil」）。
        let written = try #require(fakeInstaller.diskContents)
        #expect(delegate.codexHookStore.contents == written,
                "CodexHookStore 讀回來的位元組應與 connect() 寫出去的逐位元組相等")

        // ④ banner 含兩個關鍵詞（從 L10nCodex 鍵推導，不寫死全文）。
        let banner = try #require(delegate.currentBanner)
        #expect(banner.contains(L10nCodex.nextSessionTakesEffectKeyword)
                && banner.contains(L10nCodex.codexWillAskToTrustKeyword), """
            接上成功的 banner 必須同時講「下一個 session 起生效」與「Codex 會問你信任」（D-m），
            實際 banner：\(banner)
            """)

        // ⑤ spy 記 probe() 次數：onOpen 之後必須增加。
        let onOpen = try #require(spy.onOpen, "AppDelegate 沒有接 status.onOpen")
        let before = fakeInstaller.probeCallCount
        onOpen()
        #expect(fakeInstaller.probeCallCount > before,
                "onOpen 必須觸發 reprobeCodex()（CX24⑤），probe 次數應該增加")
        #else
        Issue.record("""
            待 T10：AppDelegate+Codex.swift／CodexHookStore／L10nCodex 尚未存在，\
            composition-root 五段接線無法驗證。T10 落地後把本測試函式裡的 \
            #if AURA_CODEX_PENDING_T10 / #else / #endif 拿掉，依實際簽章調整呼叫即可生效。
            """)
        #endif
    }
}
