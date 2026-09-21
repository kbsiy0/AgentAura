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
                                                                        inDownloads: false, writeToPasteboard: { _ in }),
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
    }

    /// CX25（§6.2 第二條）：不覆寫 `codexDependencies` 時，生產注入的是真的 `CodexInstaller`，
    /// `codexHome` 是真的 `~/.codex`——同 `AppDelegateCompositionInjectionTests
    /// .productionUsesRealInstaller` 對 Claude 側的既有先例，`probe()` 只讀不寫，
    /// 不違反「測試裡絕不碰真的 ~/.codex」（見 `AppDelegatePanelActionsWiredTests.Recorder`
    /// 的 doc comment：唯讀可以援用那個先例，`connect`／`disconnect` 不能）。
    @Test("productionCodexHomeIsRealHome：不覆寫 codexDependencies 時，codexHome 是真的 ~/.codex")
    func productionCodexHomeIsRealHome() throws {
        // 不需要 launch——codexRuntime 是 init 就算好的欄位，建構完就在。
        let delegate = AppDelegate(root: FileManager.default.temporaryDirectory)
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

    /// 建一個 `pathRejection`／`codexState` 都可控的 delegate，供 CX35／CX39 共用。
    private func makeDelegate(translocated: Bool, inDownloads: Bool = false,
                              fakeInstaller: FakeCodexInstaller) throws -> (delegate: AppDelegate, spy: SpyRenderer,
                                                                            cleanup: () -> Void) {
        let (defaults, suite) = try freshDefaults()
        let spy = SpyRenderer()
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   codexDependencies: CodexDependencies(installer: fakeInstaller, translocated: translocated,
                                                                        inDownloads: inDownloads, writeToPasteboard: { _ in }),
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

    /// CX25 來源掃描半——`codexHome` 的生產路徑不得用 `environment["HOME"]`（T04 review M1／M2
    /// 同一個陷阱已出現兩次：`timeout`／`agentFlag`；掃描本身不能拿產生器跟自己比，但這裡驗的
    /// 是「有沒有用這個字面」，不是「產生器輸出是否正確」，字面掃描是對的工具）。**只掃
    /// `Sources/`**——`Tests/`／`docs/` 裡出現這個字面是在講這件事，不是在做這件事。
    @Test("productionCodexHomeIsRealHome 來源掃描：Sources/ 不得用 environment[\"HOME\"] 算 codexHome")
    func productionCodexHomeSourceNeverReadsHomeEnvVar() throws {
        let sourcesRoot = Self.repoRoot().appendingPathComponent("Sources")
        let offenders = Self.swiftFiles(under: sourcesRoot).compactMap { url -> String? in
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  text.contains("environment[\"HOME\"]") else { return nil }
            return url.lastPathComponent
        }
        #expect(offenders.isEmpty, """
            \(offenders) 用了 environment["HOME"] 算路徑——codexHome／claudeHome 都必須用
            FileManager.default.homeDirectoryForCurrentUser，不是環境變數（CX25）
            """)
    }

    /// 同一個 target 看不到 `Tests/AuraCoreTests/Gate.swift`，各自維護一份小型
    /// `repoRoot()`（同 `AboutContentTests` 的既有先例）。
    static func repoRoot() -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        while dir.pathComponents.count > 1 {
            dir = dir.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir
            }
        }
        fatalError("找不到 Package.swift")
    }

    static func swiftFiles(under root: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
