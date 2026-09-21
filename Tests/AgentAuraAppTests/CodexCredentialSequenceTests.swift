import Testing
import Foundation
@testable import AgentAuraApp
import AuraCore
import AuraHookFile

/// CX42（R-8 不變式 1 的憑證半，r4 M3）：`CodexCoexistenceSequenceTests`（AuraHookFile，
/// CX37a／CX37b）只看得到**檔案**這一半；`InstallState` 還吃 App 層的三個 `AgentAuraHook*`
/// 鍵、`CodexState` 還吃 `AgentAuraCodexHookContents`。風險就在那一半：`performDisconnect()`
/// （Claude）清到 Codex 的鍵、`performConnectCodex()` 寫到 Claude 的鍵、或新程式碼順手
/// `removePersistentDomain`——全是本 change 才新增的程式碼。**doc comment 互相點名**：
/// 這裡守的是憑證半，檔案半在 `Tests/AuraCoreTests/CodexCoexistenceSequenceTests.swift`。
///
/// **定義域**：`{performConnect, performDisconnect, performConnectCodex,
/// performDisconnectCodex}` 的全部長度 ≤ 2 序列＝4 個長度 1 ＋ 16 個長度 2＝20 條
/// （程式推導，見 `allSequencesUpToLength2()`，不手列）。每條序列各自一份全新 fixture＋
/// 全新 `AppDelegate`，不跨序列共用狀態（同 `AppDelegatePanelActionsWiredTests` 的
/// T10b bug B 教訓）。
///
/// **Codex 側全記憶體、零 spawn**（`FakeCodexInstaller`）；**Claude 側是既有的真
/// `Installer`**（`AppInstallerFixture`，temp fixture，throwaway）——`performConnect`
/// 從未連上的狀態轉成已連上時，`Installer.connect` 內部會走到 `verifyByExecuting`
/// 真的 spawn 一次 `aura-hook`（同一顆已建好的二進位，`withFreshRig` 的 `.connect` case
/// 也是這樣做），已連上之後再 `connect` 是早退、不 spawn；`performDisconnect()`／
/// `performConnectCodex()`／`performDisconnectCodex()` 三者從不 spawn。**與計畫原文
/// 「全記憶體、零 spawn」的差異**：那句話對 Codex 側成立、對 Claude 側的
/// `performConnect`（從未連上狀態轉連上）不成立——`AppDelegate.installer` 是具體型別
/// `Installer`，composition root 沒有給它留協定注入縫，測不到「完全不碰 Installer 真
/// 實作」這件事；20 條序列裡最多 8 條會各觸發一次真 spawn（單一 `[performConnect]`
/// ＋ 7 條含 `performConnect` 的長度 2 序列），每次都經過 `SpawnGate` 序列化，量級與
/// 既有 `.replaceExternalMount`／CX37b 相近，不是新增的風險。
@MainActor
@Suite("Codex／Claude 憑證序列互不干擾（CX42）", .serialized)
struct CodexCredentialSequenceTests {

    enum Action: String, CaseIterable, CustomStringConvertible {
        case performConnect, performDisconnect, performConnectCodex, performDisconnectCodex
        var description: String { rawValue }
    }

    /// 全部長度 ≤ 2 的序列：4 個長度 1 ＋ 16 個長度 2（4×4 排列，含同一動作連續兩次）。
    /// `nonisolated`：`@Test(arguments:)` 的參數運算式在 macro 展開處求值，不在
    /// `@MainActor` 隔離域內——這個函式本身零狀態、純運算，隔離沒有意義。
    nonisolated static func allSequencesUpToLength2() -> [[Action]] {
        let singles = Action.allCases.map { [$0] }
        let pairs = Action.allCases.flatMap { first in Action.allCases.map { second in [first, second] } }
        return singles + pairs
    }

    /// Claude 側三個既有鍵（`HookVerificationStore`）；Codex 側一個鍵（`CodexHookStore.key`）。
    static let claudeKeys = ["AgentAuraHookVerified", "AgentAuraHookBlocked", "AgentAuraHookUnconfirmed"]
    static let codexKey = "AgentAuraCodexHookContents"

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-codex-credseq-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("全部 20 條 ≤2 長度序列：另一側的鍵位元組完全不變，鍵集合差集裡沒有不該出現的鍵",
          arguments: allSequencesUpToLength2())
    func bothSidesNeverDisturbEachOthersCredentials(_ sequence: [Action]) async throws {
        let layout = try AppInstallerFixture.make()
        defer { layout.cleanup() }
        let installer = AppInstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin,
                                                       verificationTimeout: 3)
        let suite = "io.agentaura.tests.codexcredseq.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fakeCodexInstaller = FakeCodexInstaller(mode: .normal)

        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults, installer: installer,
                                   makeLoginItem: { FakeLoginItem() },
                                   confirmDisconnect: { _, onConfirm in onConfirm() },
                                   codexDependencies: CodexDependencies(installer: fakeCodexInstaller, translocated: false,
                                                                        inDownloads: false, writeToPasteboard: { _ in },
                                                                        hookBinaryPath: AppDelegate.productionHookBinaryPath()),
                                   makeRenderer: { SpyRenderer() })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        for action in sequence {
            let isClaudeSideAction = action == .performConnect || action == .performDisconnect
            let beforeKeys = Set((defaults.persistentDomain(forName: suite) ?? [:]).keys)
            let beforeClaudeValues = Self.claudeKeys.map { defaults.object(forKey: $0) as? String }
            let beforeCodexValue = defaults.string(forKey: Self.codexKey)

            await SpawnGate.shared.run {
                switch action {
                case .performConnect: delegate.performConnect(force: false)
                case .performDisconnect: delegate.performDisconnect()
                case .performConnectCodex: delegate.performConnectCodex()
                case .performDisconnectCodex: delegate.performDisconnectCodex()
                }
            }

            if isClaudeSideAction {
                #expect(defaults.string(forKey: Self.codexKey) == beforeCodexValue, """
                    序列 \(sequence)：\(action) 之後 Codex 側鍵 \(Self.codexKey) 的位元組被改動了
                    """)
            } else {
                let afterClaudeValues = Self.claudeKeys.map { defaults.object(forKey: $0) as? String }
                #expect(afterClaudeValues == beforeClaudeValues, """
                    序列 \(sequence)：\(action) 之後 Claude 側鍵 \(Self.claudeKeys) 的位元組被改動了，\
                    改動前 \(beforeClaudeValues)，改動後 \(afterClaudeValues)
                    """)
            }

            // 差集斷言（不逐鍵列舉，鍵清單會 drift）：新增／刪除的鍵只准是這一步「自己那一側」
            // 預期會動的鍵；`didConnectOnceKey` 是 Claude 側自己的旗標，跟 Codex 側鍵集合
            // 互斥，仍算「自己那一側」。**用 `persistentDomain(forName:)`，不是
            // `dictionaryRepresentation()`**——後者是整條搜尋鏈合併後的效果值，含
            // `NSGlobalDomain`／registration domain；別的測試在同一個行程裡第一次初始化
            // 某個 AppKit 文字元件時，會把 `NSUsesTextStylesForLineBreaks` 這類鍵寫進
            // 全域 domain，讓這條差集斷言在全量套件裡偶爾誤紅（實測抓到過一次）。只看
            // 這個 suite 自己的 persistent domain 才是這條不變式真正在問的範圍。
            let afterKeys = Set((defaults.persistentDomain(forName: suite) ?? [:]).keys)
            let ownSideKeys: Set<String> = isClaudeSideAction
                ? Set(Self.claudeKeys + [AppDelegate.didConnectOnceKey])
                : [Self.codexKey]
            let unexpected = beforeKeys.symmetricDifference(afterKeys).subtracting(ownSideKeys)
            #expect(unexpected.isEmpty, """
                序列 \(sequence)：\(action) 之後有非預期的鍵被新增／刪除：\(unexpected)（只准動自己那一側）
                """)
        }
    }
}
