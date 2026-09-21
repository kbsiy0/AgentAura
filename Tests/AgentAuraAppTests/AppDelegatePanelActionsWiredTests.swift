import Testing
import Foundation
import AppKit
@testable import AgentAuraApp
import AuraCore
import AuraHookFile

/// G5 `panelActionsAreWired`（spec §6.2／§6.3）：`PanelActionKind.allCases.flatMap(PanelAction.samples)`
/// 逐一驗證**每一個**的副作用真的發生（含 `setLaunchAtLogin` 的 true／false 兩者）。
///
/// **T10b bug B**：舊版把全部動作依序送進「同一個」delegate，`.replaceExternalMount`／
/// `.disconnect`／`.dismissBanner` 這幾個 case 的前提條件（要嘛已連上、要嘛已有 banner）
/// 隱含依賴「前一步剛好跑完」——team-lead 實測全套件並行負載重時抓到 `.replaceExternalMount`
/// 那條斷言翻車（`banner?.kind` 還是 `.connected`，沒變成 `.alreadyConnected`）。**修法**：
/// 每個 case 各自拿全新的 delegate／installer fixture（`withFreshRig`），需要「已連上」這種
/// 前提時在該 case 自己的作用域裡明確先做一次。動作總數由
/// `PanelActionKind.allCases.flatMap(samples)` 推導（R6，不寫死數字）——T24 新增 `.uninstall`。
@MainActor
@Suite("G5：panelActionsAreWired", .serialized)
struct AppDelegatePanelActionsWiredTests {

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-actionswired-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    func wait(upTo seconds: TimeInterval, until cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if cond() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// 一個 case 需要回報的可變副作用——每個 case 各自建一份全新的，不跨 case 共用。
    @MainActor
    final class Recorder {
        let fakeLoginItem = FakeLoginItem()
        let fakeTerminator = FakeTerminator()
        var openedURLs: [URL] = []
        /// T12（B4）：不再只數呼叫次數——存下拿到的字典，斷言含版本＋專案連結（不是只斷言「被呼叫」）。
        var aboutOptions: [NSApplication.AboutPanelOptionKey: Any]?
        var confirmedDisconnects = 0
        /// A5（T11 commit3）：`.replaceExternalMount` 現在也要先走確認框，同 `confirmedDisconnects`。
        var confirmedReplaceExternalMounts = 0
        var confirmedUninstalls = 0   // T24：`.uninstall` 同理
        /// T32：`.pickIconShape` 每次真的走過選單呈現閉包才 +1——同 `confirmedDisconnects`
        /// 的理由，證明這一步沒有被跳過。
        var presentedIconShapeMenuCount = 0
        /// T10：`AppDelegate.init` 的 `codexDependencies` 預設值是**真的** `.production()`
        /// （同 Claude 側 `installer: Installer = .production()` 的既有先例）——`withFreshRig`
        /// 若不明確覆寫，`.connectCodex`／`.disconnectCodex` 會真的打中這台機器的
        /// `~/.codex/hooks.json`（`reprobeCodex()` 的 `probe()` 是唯讀，可以比照
        /// `AppDelegateCompositionInjectionTests` 的既有先例不覆寫；`connect`／`disconnect`
        /// 會寫，不能援用那個先例）。**每個 case 全新一份**，不跨 case 共用。
        let fakeCodexInstaller = FakeCodexInstaller(mode: .normal)
        var pasteboardWrites: [String] = []
    }

    @MainActor
    struct Rig {
        let layout: AppInstallerFixture.Layout
        let delegate: AppDelegate
        let spy: SpyRenderer
        let recorder: Recorder
        let onAction: (PanelAction) -> Void
    }

    /// 每個 case 專用的全新 rig：全新 fixture＋全新 delegate，`applicationDidFinishLaunching`
    /// 已經呼叫過。fixture 尚未連上（`AppInstallerFixture.make()` 不含 `linkDirectly`），
    /// 這裡的 launch 本身不會觸發背景驗證、不 spawn——需要「已連上」前提的 case 由呼叫端
    /// 自己在 body 裡明確做（例如先 `SpawnGate.shared.run { rig.onAction(.connect) }`）。
    func withFreshRig(_ body: (Rig) async throws -> Void) async throws {
        let layout = try AppInstallerFixture.make()
        defer { layout.cleanup() }
        let installer = AppInstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin,
                                  verificationTimeout: 3)
        let suite = "io.agentaura.tests.actionswired.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let spy = SpyRenderer()
        let recorder = Recorder()

        let delegate = AppDelegate(
            root: try makeRoot(), livenessInterval: 0.05, defaults: defaults, installer: installer,
            makeLoginItem: { recorder.fakeLoginItem },
            openURL: { recorder.openedURLs.append($0) },
            showAboutPanel: { recorder.aboutOptions = $0 },
            terminator: recorder.fakeTerminator,
            confirmDisconnect: { _, onConfirm in recorder.confirmedDisconnects += 1; onConfirm() },
            confirmReplaceExternalMount: { _, onConfirm in recorder.confirmedReplaceExternalMounts += 1; onConfirm() },
            confirmUninstall: { _, onConfirm in recorder.confirmedUninstalls += 1; onConfirm() },
            presentIconShapeMenu: { current, _, _, _, onSelect in recorder.presentedIconShapeMenuCount += 1; onSelect(current) },
            codexDependencies: CodexDependencies(installer: recorder.fakeCodexInstaller, translocated: false, inDownloads: false,
                                                 writeToPasteboard: { recorder.pasteboardWrites.append($0) }),
            makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }
        let onAction = try #require(spy.onAction, "AppDelegate 沒有接 status.onAction")

        try await body(Rig(layout: layout, delegate: delegate, spy: spy, recorder: recorder, onAction: onAction))
    }

    @Test("PanelActionKind.allCases.flatMap(samples) 逐一送進 onAction，每一個都有真的副作用（各自獨立的 rig，不依賴迴圈順序）")
    func everyActionKindHasARealWiredEffect() async throws {
        for kind in PanelActionKind.allCases {
            let samples = PanelAction.samples(kind)
            #expect(!samples.isEmpty, ".\(kind) 的 samples 不該是空的")

            switch kind {
            case .pickColor:
                try await withFreshRig { rig in
                    for action in samples { rig.onAction(action) }
                    #expect(rig.spy.pinned.last == true, ".pickColor 應該把 popover 釘住（setPopoverPinned(true)）")
                }
            case .resetColors:
                try await withFreshRig { rig in
                    rig.delegate.applyColor(RGBA(r: 0.9, g: 0.1, b: 0.2, a: 1), for: .waiting)
                    #expect(rig.spy.panels.last?.isDefaultPalette == false, "前提：改色後 isDefaultPalette 應為 false")
                    for action in samples { rig.onAction(action) }
                    #expect(rig.spy.panels.last?.isDefaultPalette == true, ".resetColors 之後 isDefaultPalette 應回到 true")
                }

            case .toggleOptions:
                try await withFreshRig { rig in
                    #expect(rig.delegate.optionsExpanded == false, "前提：Options 預設收合")
                    for action in samples { rig.onAction(action) }
                    #expect(rig.delegate.optionsExpanded == true, ".toggleOptions 之後 optionsExpanded 應變 true")
                }

            case .connect:
                try await withFreshRig { rig in
                    await SpawnGate.shared.run {
                        for action in samples { rig.onAction(action) }
                    }
                    guard case .connected(.thisApp, .verified) = rig.delegate.installState else {
                        Issue.record(".connect 之後應該是 connected(.thisApp, .verified)，實際 \(rig.delegate.installState)")
                        return
                    }
                    #expect(rig.delegate.banner?.kind == .connected, ".connect 成功後應顯示「已接上」banner")
                }

            // T10：body 搬到 +Codex.swift（純搬移，替 CX24／CX25／CX26／CX31／CX35／CX39／
            // CX40／CX42 這批新斷言在 300 行上限的主檔裡留出空間，同 T12／T16 那幾個 case 的理由）。
            case .replaceExternalMount: try await verifyReplaceExternalMount(samples: samples)

            case .disconnect:
                try await withFreshRig { rig in
                    await SpawnGate.shared.run { rig.onAction(.connect) }
                    guard case .connected(.thisApp, .verified) = rig.delegate.installState else {
                        Issue.record("前置條件失敗：先 connect 一次應該成功，實際 \(rig.delegate.installState)")
                        return
                    }
                    for action in samples { rig.onAction(action) }   // disconnect 本身不 spawn，不必經過 SpawnGate
                    #expect(rig.recorder.confirmedDisconnects == 1, ".disconnect 應該先走過確認對話框閉包")
                    #expect(rig.delegate.installState == .notConnected, ".disconnect 之後應該回到 notConnected")
                    #expect(rig.delegate.banner?.kind == .disconnected, ".disconnect 成功後應顯示「已移除掛載」banner")
                }

            case .uninstall:   // T24：case body 在 `+Uninstall.swift`（同 T12／T16，避免撞 300 行上限）
                try await verifyUninstall(samples: samples)

            case .setLaunchAtLogin:
                try await withFreshRig { rig in
                    #expect(samples.contains(.setLaunchAtLogin(true)) && samples.contains(.setLaunchAtLogin(false)),
                           "N7：兩個布林都要送，實際 \(samples)")
                    for action in samples {
                        guard case .setLaunchAtLogin(let on) = action else { continue }
                        let before = rig.recorder.fakeLoginItem.setCallCount
                        rig.onAction(action)
                        #expect(rig.recorder.fakeLoginItem.setCallCount == before + 1, ".setLaunchAtLogin(\(on)) 應該呼叫 loginItem.set")
                        #expect(rig.delegate.launchAtLogin == on, "設完應重讀實際值，應為 \(on)，實際 \(String(describing: rig.delegate.launchAtLogin))")
                    }
                }

            case .recheckHook:
                try await withFreshRig { rig in
                    // 重新接上（繞過 onAction，直接用注入的 fixture 建立掛載）但**不**經過完整
                    // connect 流程，模擬 verification == .unknown 的狀態，讓 recheckHook 有東西可驗。
                    try AppInstallerFixture.linkDirectly(rig.layout)
                    await SpawnGate.shared.run {
                        for action in samples { rig.onAction(action) }
                        await wait(upTo: 10) {
                            if case .connected(_, .verified) = rig.delegate.installState { return true }
                            return false
                        }
                    }
                    guard case .connected(_, .verified) = rig.delegate.installState else {
                        Issue.record(".recheckHook 之後應該驗證成功變成 connected(_, .verified)，實際 \(rig.delegate.installState)")
                        return
                    }
                }

            case .openHelp: try await verifyOpenHelp(samples: samples)   // E3：body 在 +E3.swift（避免撞 300 行上限）
            case .about: try await verifyAbout(samples: samples)   // T12（B4）：body 在 +T12.swift

            case .dismissBanner:
                try await withFreshRig { rig in
                    // 前置條件：先 connect 一次，讓它留下一條 banner，再測 dismissBanner
                    // 真的把它清掉——不依賴迴圈裡「上一個 case 剛好留了什麼」（T10b bug B）。
                    await SpawnGate.shared.run { rig.onAction(.connect) }
                    #expect(rig.delegate.banner != nil, "前提：connect 之後應該留下一條 banner")
                    for action in samples { rig.onAction(action) }
                    #expect(rig.delegate.banner == nil, ".dismissBanner 之後 banner 應為 nil")
                }

            case .quit: try await verifyQuit(samples: samples)   // T10：body 搬到 +Codex.swift（同上）

            // T12（B2／B5）：case body 移到 `AppDelegatePanelActionsWiredTests+T12.swift`（避免撞 300 行上限）。
            case .reportIssue:
                try await verifyReportIssue(samples: samples)

            case .setReduceMotion:
                try await verifySetReduceMotion(samples: samples)

            case .setIconPlate:   // T16：case body 在 `+T16.swift`（同上，避免撞 300 行上限）
                try await verifySetIconPlate(samples: samples)
            case .setLanguage: try await verifyLanguage(samples: samples)   // T26：body 在 +Language.swift
            case .pickIconShape: try await verifyIconShape(samples: samples)   // T32：body 在 +IconShape.swift
            case .connectCodex, .disconnectCodex, .copyCodexSnippet: try await verifyCodexActionsAreStubbed(kind: kind, samples: samples)   // T07：body 在 +Codex.swift
            }
        }
    }

    /// A5（T11 commit3）：`performConnect(force: true)` 在非早退情境（真的換掉一份外部掛載，
    /// 不是「本來就已接上」那個早退分支）下要顯示 `mountReplaced` banner、帶著換掉前的目標
    /// 路徑——不是沿用普通 `.connected()` 那句「下一個 session 起生效」，那句話不提「換了誰」。
    /// 直接呼叫 `performConnect`（略過確認框那一層，那一層由上面 `.replaceExternalMount` 的
    /// case 另外驗）：`Installer.replaceExternalMount` 的正確性已由 `InstallerTests`
    /// （AuraCoreTests）驗過，這裡只驗 `AppDelegate` 選對了 banner 建構式。
    @Test("performConnect(force: true) 非早退時顯示 mountReplaced banner，帶原掛載路徑")
    func performConnectForceShowsMountReplacedBanner() async throws {
        try await withFreshRig { rig in
            rig.delegate.externalTargetPath = "/Users/dev/old-repo/plugin"   // 模擬換掉前的舊掛載
            await SpawnGate.shared.run { rig.delegate.performConnect(force: true) }
            guard case .connected(.thisApp, .verified) = rig.delegate.installState else {
                Issue.record("前置條件失敗：force connect 應該成功，實際 \(rig.delegate.installState)")
                return
            }
            #expect(rig.delegate.banner?.kind == .connected, "mountReplaced 沿用 .connected kind（視覺上仍是成功樣式）")
            #expect(rig.delegate.banner?.text.contains("/Users/dev/old-repo/plugin") == true, """
                banner 文案應該明說原掛載路徑，實際「\(String(describing: rig.delegate.banner?.text))」
                """)
        }
    }

    /// `disconnectDoesNotAcknowledge`（spec §6.2／S1-A9）：disconnect 之後尾巴仍在、狀態檔仍在。
    /// 獨立測試，不受上面那條的重構影響——`disconnect()` 本身不 spawn，維持原樣。
    @Test("disconnect 不 acknowledge：已結束的列與狀態檔在 disconnect 之後都還在")
    func disconnectDoesNotAcknowledge() async throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "disc-ended", root: root) { _ in
            var s = SessionSnapshot(sessionID: "disc-ended")
            s.mainActivity = .done; s.terminated = true; s.writtenAt = Date(); return s
        }
        let layout = try AppInstallerFixture.make()
        defer { layout.cleanup() }
        try AppInstallerFixture.linkDirectly(layout)
        let installer = AppInstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)
        let suite = "io.agentaura.tests.discack.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let spy = SpyRenderer()
        let delegate = AppDelegate(root: root, livenessInterval: 0.05, defaults: defaults, installer: installer,
                                   makeLoginItem: { FakeLoginItem() },
                                   confirmDisconnect: { _, onConfirm in onConfirm() }, makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        await wait(upTo: 10) { spy.panels.last?.rows.contains { $0.isEnded } == true }
        #expect(spy.panels.last?.rows.contains { $0.isEnded } == true, "前提：已結束的列要先進得了面板 model")

        let onAction = try #require(spy.onAction)
        onAction(.disconnect)

        #expect(delegate.installState == .notConnected, "disconnect 之後應該回到 notConnected")
        #expect(spy.panels.last?.rows.contains { $0.isEnded } == true, """
            disconnect 之後已結束的列消失了 —— acknowledge 被觸發，違反 S1-A9
            （disconnect 不得呼叫 acknowledgeAll()）
            """)
        #expect(SnapshotIO.allSessionIDs(root: root).contains("disc-ended"), """
            disconnect 之後狀態檔應該還在，實際 \(SnapshotIO.allSessionIDs(root: root))
            """)
    }
}
