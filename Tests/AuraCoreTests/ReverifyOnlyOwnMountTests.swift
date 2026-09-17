import Testing
import Foundation
import AuraCore
@testable import AuraHookFile

/// 公開前稽核（攻擊面 #1）：`reverifyCurrentMount()` 只准驗**自己的**掛載。
///
/// 這條路徑會 `removexattr` 拆掉目標的 `com.apple.quarantine` 再 exec 它，而且由
/// `AppDelegate.launchVerificationIfNeeded` 在**啟動時自動跑、零使用者確認**。
/// 稽核前它只檢查「那個位置有東西」，不檢查那是不是這個 app 自己 bundle 裡的那一份——
/// 於是使用者若手動 `ln -sfn` 把掛載指到別人給的目錄（README 與 INSTALL 都教過這個指令），
/// AgentAura 會**主動替那份不是自己的程式碼拆掉 Gatekeeper 的保護，然後執行它**。
///
/// 嚴重度要講清楚：掛載一旦指過去，Claude Code 本來每個 hook 事件就會執行那顆二進位，
/// 所以 AgentAura 不是這條鏈上最弱的一環，這也不是遠端可利用的漏洞。
/// 但「自動、無聲、替不是自己的二進位拆保護」不該是背景驗證做的事——外部掛載要驗，
/// 走使用者明確按下、且有確認框的 `replaceExternalMount`。
///
/// **稽核當下沒有任何測試覆蓋這條路徑**（加了 guard 之後全套件仍然全綠），這個檔案補上。
@Suite("背景驗證只碰自己的掛載")
struct ReverifyOnlyOwnMountTests {

    @Test("掛載指向別人的目錄時，reverifyCurrentMount 拒絕（不拆 quarantine、不 exec）")
    func refusesToVerifyForeignMount() async throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        // 另一份獨立、真的能跑的「外部」plugin —— 同 InstallerClobberTests 的既有做法。
        let external = try InstallerFixture.make()
        defer { external.cleanup() }

        try FileManager.default.createDirectory(at: layout.claudeHome.appendingPathComponent("skills"),
                                                withIntermediateDirectories: true)
        let target = layout.claudeHome.appendingPathComponent("skills/agentaura")
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: external.bundlePlugin)

        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome,
                                                   bundlePluginURL: layout.bundlePlugin)
        // 經 `SpawnGate`：`reverifyCurrentMount` 在沒被擋下時真的會 spawn，
        // 全套件並行下不排隊就會搶行程資源（T10b）。這裡預期它被擋下，但閘門要照走——
        // 「因為我預期它不會 spawn 所以不必排隊」正是會被下一次改動推翻的假設。
        await SpawnGate.shared.run {
            #expect(throws: (any Error).self) {
                _ = try installer.reverifyCurrentMount()
            }
        }
    }

    /// 反向對照：掛載就是自己 bundle 裡那一份時，**必須照驗不誤**。
    /// 少了這條，上面那條可以用「永遠 throw」通過——那會讓背景驗證整個失效，
    /// 而使用者看到的是 icon 永遠停在未驗證。
    @Test("掛載就是自己那一份時，reverifyCurrentMount 照常驗證")
    func verifiesOwnMount() async throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }

        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome,
                                                   bundlePluginURL: layout.bundlePlugin)
        try await SpawnGate.shared.run {
            _ = try installer.connect(force: false, translocated: false, inDownloads: false)
            let (obs, stamp) = try installer.reverifyCurrentMount()
            #expect(!stamp.isEmpty, "自己的掛載應該驗得出 stamp")
            #expect(obs.targetIdentity == obs.thisAppPluginIdentity,
                    "前提：connect 之後掛載應該指向 bundle 內建的那一份")
        }
    }
}
