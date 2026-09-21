import Testing
import Foundation
@testable import AgentAuraApp
import AuraCore
import AuraHookFile

/// T10：composition-root smoke（spec §6.2／§6.3）——驗 `AppDelegate+Codex.swift` 真的把
/// `CodexInstaller`／`CodexHookStore`／`reprobeCodex()` 接起來，而不是「單元測試證明能用、
/// composition root 忘了傳」（user-level CLAUDE.md「Tested-capability ≠ wired-capability」）。
///
/// **CX24 五段**：
/// ① 接線：`delegate` 真的持有注入的 codex 依賴，不是 nil／換成生產預設值。
/// ② fake 收到 `connect()` 呼叫：送出接上動作之後，fake 的呼叫序裡有一次 "connect"。
/// ③ 憑證取回是同一串位元組：`connect()` 回傳的 `Data` 與 `CodexHookStore` 讀回來的
///    **逐位元組**相等——不是「非 nil」，這正是「tested-capability ≠ wired-capability」
///    的反例（round-trip 若被悄悄改過，這一段才抓得到，②只證明呼叫發生了）。
/// ④ banner 含兩個關鍵詞（下一個 session 起生效／需要在 Codex 裡按同意，D-m）：
///    從 `L10nCodex` 的鍵推導，不寫死中文全文，語言一換也要能跟著換。
/// ⑤ spy 記 `probe()` 次數：`onOpen` 之後 `probeCallCount` 必須比呼叫前更多
///    （`reprobeCodex()` 四個時機之一；漏接的症狀是「裝了 Codex、開面板、什麼都沒有，
///    重開才出現」，見 spec §4.6）。**這一段比對位元組**（`fakeInstaller.probeCallCount`
///    是計數，不是位元組——這裡指的是 mutation③「拿掉 onOpen 的 reprobeCodex()」時，
///    唯一會變的就是這個計數，其餘四段的斷言在那個 mutation 下仍然照樣通過）。
@MainActor
@Suite("Codex composition-root smoke（CX24／CX25）", .serialized)
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
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let spy = SpyRenderer()
        let fakeInstaller = FakeCodexInstaller(mode: .normal)

        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   codexDependencies: CodexDependencies(installer: fakeInstaller, translocated: false,
                                                                        inDownloads: false, writeToPasteboard: { _ in },
                                                                        hookBinaryPath: AppDelegate.productionHookBinaryPath()),
                                   makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        // ① 接線：注入的依賴真的被持有，不是 nil／換成生產預設值。
        #expect(delegate.codexRuntime.installer is FakeCodexInstaller,
                "composition root 沒有把注入的 fake 接上，實際型別 \(type(of: delegate.codexRuntime.installer))")

        // ② fake 收到 connect() 呼叫——**走 onAction**（不是直接呼叫 `performConnectCodex()`），
        // 這樣「`switch action` 的 `.connectCodex` 分支改 break」才會讓這一段真的變紅
        // （mutation①；直接呼叫方法會繞過那個 switch，測不到接線本身斷掉）。
        let onAction = try #require(spy.onAction, "AppDelegate 沒有接 status.onAction")
        onAction(.connectCodex)
        #expect(fakeInstaller.connectCallCount == 1, "送出接上動作之後，fake 應該收到恰一次 connect()")

        // ③ 憑證取回是同一串位元組（不是「非 nil」）。
        let written = try #require(fakeInstaller.diskContents)
        #expect(delegate.codexRuntime.store.contents == written,
                "CodexHookStore 讀回來的位元組應與 connect() 寫出去的逐位元組相等")

        // ④ banner 含兩個關鍵詞（從 L10nCodex 鍵推導，不寫死全文）。
        let banner = try #require(delegate.banner?.text)
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

        // T10 裁決 3（取代文字掃描「PanelModel.make(」呼叫點）：refreshPanel() 真的把
        // codexState／codexSnippet／codexPathRejection 交給 status.setPanel，不是寫死字面。
        // **前提先釘住 `codex != .unavailable`**（review m2）——否則下面的等式在
        // `.unavailable == .unavailable` 這種退化情況下也會恆真。
        let lastPanel = try #require(spy.panels.last, "onOpen 之後應該至少畫過一次面板")
        #expect(lastPanel.codex != .unavailable, """
            前提：connect 成功之後 codexState 不該還是 .unavailable，否則下面的等式斷言\
            會退化成拿兩個 .unavailable 互相比對
            """)
        #expect(lastPanel.codex == delegate.codexRuntime.codexState, """
            status.setPanel 收到的 PanelModel.codex 應等於 codexRuntime.codexState，\
            實際 panel=\(lastPanel.codex) runtime=\(delegate.codexRuntime.codexState)
            """)
        #expect(lastPanel.codexPathRejection == delegate.codexRuntime.pathRejection, """
            status.setPanel 收到的 PanelModel.codexPathRejection 應等於行程常數 \
            codexRuntime.pathRejection
            """)
        // review M1：codexSnippet 完全沒有被斷言過——先釘住這條 rig 下它非 nil
        // （pathRejection == nil），再比對相等，避免又是一次「兩邊都 nil」的恆真。
        #expect(delegate.codexRuntime.codexSnippet != nil, """
            前提：pathRejection == nil 時應該有 snippet 可複製，否則下面的等式斷言會退化成
            拿兩個 nil 互相比對
            """)
        #expect(lastPanel.codexSnippet == delegate.codexRuntime.codexSnippet, """
            status.setPanel 收到的 PanelModel.codexSnippet 應等於 codexRuntime.codexSnippet，\
            實際 panel=\(String(describing: lastPanel.codexSnippet)) \
            runtime=\(String(describing: delegate.codexRuntime.codexSnippet))
            """)
    }

    /// review M1（另一半）：路徑被拒時，`refreshPanel()` 交給 `status.setPanel` 的
    /// `codexPathRejection` 必須真的是 `.mustMoveToApplications`、`codexSnippet` 必須真的是
    /// `nil`（R-10）——`codexConnectChainIsWired` 那條 rig 的 `pathRejection` 恆為 `nil`，
    /// 測不到這一半；這裡用 `translocated: true` 開一個 `pathRejection != nil` 的 rig。
    @Test("被拒路徑：status.setPanel 收到的 codexPathRejection／codexSnippet 跟著行程常數走")
    func refreshPanelCarriesRejectedPathState() throws {
        let fakeInstaller = FakeCodexInstaller(mode: .normal)
        let (delegate, spy, cleanup) = try makeDelegate(translocated: true, fakeInstaller: fakeInstaller)
        defer { cleanup() }

        let lastPanel = try #require(spy.panels.last, "launch 之後應該至少畫過一次面板")
        #expect(lastPanel.codexPathRejection == .mustMoveToApplications, """
            translocated: true 時 codexPathRejection 應該是 .mustMoveToApplications，\
            實際 \(String(describing: lastPanel.codexPathRejection))
            """)
        #expect(lastPanel.codexSnippet == nil, """
            .mustMoveToApplications 時 codexSnippet 必須被扣住（R-10），\
            實際 \(String(describing: lastPanel.codexSnippet))
            """)
    }

    /// CX25（§6.2 第二條）：顯式傳 `.production()` 時，生產注入的是真的 `CodexInstaller`，
    /// `codexHome` 是真的 `~/.codex`——同 `AppDelegateCompositionInjectionTests
    /// .productionUsesRealInstaller` 對 Claude 側的既有先例，`probe()` 只讀不寫，
    /// 不違反「測試裡絕不碰真的 ~/.codex」（見 `AppDelegatePanelActionsWiredTests.Recorder`
    /// 的 doc comment：唯讀可以援用那個先例，`connect`／`disconnect` 不能）。**review M3
    /// 拿掉 `codexDependencies` 的預設值之後，這裡已經不是「不覆寫」，是明確傳同一個生產值**
    /// ——測的事情（生產值本身是真的）完全不變，只是不再靠隱式預設達成。
    @Test("productionCodexHomeIsRealHome：顯式傳 .production() 時，codexHome 是真的 ~/.codex")
    func productionCodexHomeIsRealHome() throws {
        // 不需要 launch——codexRuntime 是 init 就算好的欄位，建構完就在。
        let delegate = AppDelegate(root: FileManager.default.temporaryDirectory, codexDependencies: .production())
        guard let installer = delegate.codexRuntime.installer as? CodexInstaller else {
            Issue.record("""
                生產注入的 codexRuntime.installer 型別是 \(type(of: delegate.codexRuntime.installer))，\
                不是真的 CodexInstaller——composition root 沒有接上生產實作
                """)
            return
        }
        let path = installer.codexHome.path
        #expect(path.hasSuffix("/.codex"), "生產 codexHome 應以 /.codex 結尾，實際 \(path)")
        #expect(!path.hasPrefix("/var/folders/"), """
            生產 codexHome 不該落在 /var/folders/ 下（那是測試注入的 temp 值），實際 \(path)
            """)
        #expect(!path.hasPrefix(NSTemporaryDirectory()), "生產 codexHome 不該落在 NSTemporaryDirectory() 下，實際 \(path)")
    }

    /// 建一個 `pathRejection`／`codexState` 都可控的 delegate，供 CX35／CX39／review M5
    /// 共用——**internal，不是 private**：M5 三個對抗式 mode 測試搬到
    /// `+Adversarial.swift`（同一個 test target 的既有慣例，見
    /// `AppDelegatePanelActionsWiredTests+Codex.swift` 對 `withFreshRig` 的做法），
    /// 跨檔 extension 碰不到 `private`。
    /// review m8：`hookBinaryPath` 可覆寫（預設仍是生產路徑）——CX40 App 半的乘積表用它
    /// 補回第三欄（`.unsupportedCharacter`），其餘呼叫端不受影響。
    func makeDelegate(translocated: Bool, inDownloads: Bool = false,
                              hookBinaryPath: String = AppDelegate.productionHookBinaryPath(),
                              fakeInstaller: FakeCodexInstaller) throws -> (delegate: AppDelegate, spy: SpyRenderer,
                                                                            cleanup: () -> Void) {
        let (defaults, suite) = try freshDefaults()
        let spy = SpyRenderer()
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   codexDependencies: CodexDependencies(installer: fakeInstaller, translocated: translocated,
                                                                        inDownloads: inDownloads, writeToPasteboard: { _ in },
                                                                        hookBinaryPath: hookBinaryPath),
                                   makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        return (delegate, spy, {
            delegate.applicationWillTerminate(Notification(name: .init("test")))
            defaults.removePersistentDomain(forName: suite)
        })
    }

    /// CX35（前提：`pathRejection == nil`）：`.connectedStalePath` 下送 `.connectCodex`
    /// → 呼叫順序是 `disconnect` → `connect`；`.notConnected` 下只有 `connect`。
    @Test("CX35：.connectedStalePath 下 disconnect 先於 connect；.notConnected 下只有 connect",
          arguments: [(CodexState.connectedStalePath, ["disconnect", "connect"]),
                      (CodexState.notConnected, ["connect"])])
    func stalePathReconnectDisconnectsBeforeConnecting(_ fixture: (CodexState, [String])) throws {
        let (initialState, expectedOrder) = fixture
        let fakeInstaller = FakeCodexInstaller(mode: .normal)
        let (delegate, spy, cleanup) = try makeDelegate(translocated: false, fakeInstaller: fakeInstaller)
        defer { cleanup() }
        delegate.codexRuntime.codexState = initialState

        let onAction = try #require(spy.onAction, "AppDelegate 沒有接 status.onAction")
        onAction(.connectCodex)

        #expect(fakeInstaller.callOrder.filter { $0 == "disconnect" || $0 == "connect" } == expectedOrder, """
            初始狀態 \(initialState) 時，disconnect／connect 呼叫序應為 \(expectedOrder)，\
            實際 \(fakeInstaller.callOrder)
            """)
    }

    /// CX39：注入 `.connectedStalePath` ＋ `translocated: true`（r3 B1 的確切情境：路徑被拒
    /// 且狀態是 stale）→ 送 `.connectCodex` → `disconnect` 呼叫次數必須是 0、檔案內容完全
    /// 不動、banner 是 `.mustMoveToApplications` 那句——R-9 的 guard 必須在**任何**
    /// `disconnect` 之前 return。
    @Test("CX39：路徑被拒時 .connectCodex 絕不呼叫 disconnect，檔案不動，banner 是 mustMoveToApplications")
    func codexReconnectNeverDisconnectsWhenPathIsRejected() throws {
        let seeded = Data("stale-contents-not-touched".utf8)
        let fakeInstaller = FakeCodexInstaller(mode: .normal, seededDiskContents: seeded)
        let (delegate, spy, cleanup) = try makeDelegate(translocated: true, fakeInstaller: fakeInstaller)
        defer { cleanup() }
        delegate.codexRuntime.codexState = .connectedStalePath

        let onAction = try #require(spy.onAction, "AppDelegate 沒有接 status.onAction")
        onAction(.connectCodex)

        #expect(fakeInstaller.disconnectCallCount == 0, "路徑被拒時 disconnect 呼叫次數必須是 0")
        #expect(fakeInstaller.diskContents == seeded, "檔案內容應該完全不動")
        let banner = try #require(delegate.banner?.text)
        #expect(banner == L10nCodex.failureMessage(.mustMoveToApplications, language: .english), """
            banner 應該是 .mustMoveToApplications 那句，實際「\(banner)」
            """)
    }

    /// review m8：三個代表性 `pathRejection` 情境——`hookBinaryPath` 併入 `CodexDependencies`
    /// 之後（見 `AppDelegate+Codex.swift` doc comment）這一層終於有注入縫，CX40 App 半的
    /// 乘積表補回第三欄，不必再全部留給純函式半。
    private enum PathScenario: CaseIterable { case clean, mustMoveToApplications, unsupportedCharacter }

    /// CX40（App 半，決策層，R-10）：`CodexRuntime.codexSnippet` 是否被扣住只看
    /// `pathRejection`，跟 `codexState` 完全無關——乘積表跨 `CodexStateKind.allCases`
    /// （用 `CodexState.samples(kind)` 逐一設進 `codexRuntime.codexState`，含
    /// `.occupiedByOther`）× 三個代表性 `pathRejection` 情境（`.clean`／
    /// `.mustMoveToApplications`／`.unsupportedCharacter`，`PathScenario.allCases` 推導，
    /// 不手列）。純函式半（`CodexStateTests.withheldSnippetExhaustsRepresentativeRejections`）
    /// 窮盡全部 `Rejection` 樣本；這裡只取三個代表值，兩條測試互相點名，不是重複覆蓋。
    @Test("CX40：codexSnippet 是否被扣住只看 pathRejection，跨每個 CodexStateKind ＋ 三個代表性路徑情境都一致",
          arguments: CodexStateKind.allCases)
    func codexSnippetIsWithheldWhenPathWillVanish(_ kind: CodexStateKind) throws {
        for scenario in PathScenario.allCases {
            let fakeInstaller = FakeCodexInstaller(mode: .normal)
            let translocated = scenario == .mustMoveToApplications
            let hookBinaryPath = scenario == .unsupportedCharacter
                ? "/Applications/Agent Aura.app/Contents/Resources/plugin/bin/aura-hook"
                : AppDelegate.productionHookBinaryPath()
            let (delegate, _, cleanup) = try makeDelegate(translocated: translocated, hookBinaryPath: hookBinaryPath,
                                                           fakeInstaller: fakeInstaller)
            defer { cleanup() }
            for state in CodexState.samples(kind) {
                delegate.codexRuntime.codexState = state
                if scenario == .mustMoveToApplications {
                    #expect(delegate.codexRuntime.codexSnippet == nil, """
                        kind=\(kind) state=\(state) scenario=\(scenario)（pathRejection ==
                        .mustMoveToApplications）時 codexSnippet 應為 nil，實際 \
                        \(String(describing: delegate.codexRuntime.codexSnippet))
                        """)
                } else {
                    #expect(delegate.codexRuntime.codexSnippet != nil, """
                        kind=\(kind) state=\(state) scenario=\(scenario) 時 codexSnippet 應非 nil
                        """)
                }
            }
        }
    }

}
