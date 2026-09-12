import Testing
import Foundation
import AuraCore
@testable import AuraHookFile

/// T03 G4：`connectVerifiesByArtifact`（spec §6.3）。(a) 「exec 不產生產物 → throw」已由
/// T01 的 `FakeInstallerTests` 覆蓋（那組 double 就是為了這件事存在）；這裡補的是 (b)——
/// 正常路徑真的 spawn **SwiftPM 產物**確認會產出，以及沒被 spec 明講、但 §4.1 步驟 6
/// 明文要求的另外兩種寫回值（逾時／spawn 本身丟錯）。
/// `.serialized`：這個 suite 內部序列化；跨 suite 的序列化另外交給 `SpawnGate`（T10b——
/// `.serialized` 擋不住其他 suite 同時真的 spawn，機器仍會被灌滿）。
@Suite("Installer exec 驗證看產物（G4）", .serialized)
struct InstallerExecVerificationTests {

    /// **G4(b) 本體**：`verificationRootOverride` 注入一個呼叫端自己持有、connect() 不會
    /// 清掉的暫存根，connect() 回傳後獨立檢查那個目錄底下真的出現了 aura-hook 寫的狀態
    /// 檔——這是唯一能讓「整段拿掉 exec 驗證」這個 mutation 變成可觀察紅燈的方法：
    /// 單看 connect() 有沒有 throw／回傳的 stamp 字串，「真的 exec 過」與「壓根沒 exec
    /// 就回傳」分不出來（stamp 來自步驟 5 的 probe，不是步驟 6 的驗證本身）。
    @Test("正常路徑：真的 spawn SwiftPM 產物，注入的暫存根目錄底下真的出現狀態檔")
    func connectReallyExecutesRealBinaryAndProducesArtifact() async throws {
        let layout = try InstallerFixture.make()
        defer { layout.cleanup() }
        let verificationRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("aura-g4b-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: verificationRoot) }

        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin,
                                  verificationRootOverride: verificationRoot,
                                  verificationTimeout: 30)   // T06b：全套件並行時 2 秒偶發不夠
        let stamp = try await SpawnGate.shared.run {
            try installer.connect(force: false, translocated: false, inDownloads: false)
        }
        #expect(!stamp.isEmpty)

        let files = (try? FileManager.default.contentsOfDirectory(atPath: verificationRoot.path)) ?? []
        #expect(!files.isEmpty, """
            注入的暫存根目錄底下沒有任何檔案——exec 驗證要嘛沒有真的 spawn，
            要嘛 spawn 了但沒把 AGENTAURA_ROOT 接到這裡。
            """)
        // A1：只驗 `hasSuffix(".json")` 抓不到「檔名規則跟寫入端 (SnapshotIO.url) 是不是
        // 同一個來源」——兩邊各自手搓同一個字面就一起錯，也一起綠。改成用 SnapshotIO 自己
        // 的安全謂詞驗證檔名的 id 部分，把這條測試釘在 SnapshotIO 的契約上，不是字面形狀。
        #expect(files.count == 1, "驗證用暫存根目錄應該只有 aura-hook 寫下的那一顆狀態檔，實際 \(files)")
        for file in files {
            #expect(file.hasSuffix(".json"))
            let stem = String(file.dropLast(".json".count))
            #expect(SnapshotIO.isSafeSessionID(stem), """
                檔名「\(file)」的 session id 部分沒有通過 SnapshotIO.isSafeSessionID —— 這代表
                產生這個檔名的規則不是 SnapshotIO.url(for:root:) 那個唯一來源。
                """)
        }
    }

    @Test("exec 真的跑完但沒有產物（quarantine SIGKILL／arch 不符的可觀察結果）→ throw .hookBlockedOrBroken(stamp:)")
    func connectThrowsBlockedWhenBinaryProducesNoArtifact() async throws {
        let layout = try InstallerFixture.makeWithSilentHookBinary()
        defer { layout.cleanup() }
        // T08：全套件並行時 process.isRunning 的偵測本身會被拖慢，預設 2 秒偶發把「馬上結束
        // 但沒產物」誤判成逾時（.hookUnconfirmed，不是預期的 .hookBlockedOrBroken）——同 T06b。
        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin,
                                  verificationTimeout: 5)

        await SpawnGate.shared.run {
            do {
                _ = try installer.connect(force: false, translocated: false, inDownloads: false)
                Issue.record("預期 throw .hookBlockedOrBroken，卻成功了")
            } catch InstallerFailure.hookBlockedOrBroken(let stamp) {
                #expect(!stamp.isEmpty, "即使失敗也要帶著 stamp，供上層寫 AgentAuraHookBlocked（跨 probe／跨重啟存活，N1）")
            } catch {
                Issue.record("預期 .hookBlockedOrBroken，實際是 \(error)")
            }
        }

        // 憑證未定但掛載本身確實存在——probe() 之後仍看得到這個 symlink（不是 notConnected）。
        let observed = installer.probe()
        #expect(observed.entryType == .symlink)
        #expect(observed.hookBinaryExecutable == true, "看起來完好——access(X_OK) 不足以證明能跑，這正是 S0-A2 要修的")
    }

    @Test("spawn 本身丟錯（不是合法可執行格式）→ throw .hookUnconfirmed(stamp:)，不得誤指控 macOS（r6②／S2-11）")
    func connectThrowsUnconfirmedWhenSpawnItselfFails() async throws {
        let layout = try InstallerFixture.makeWithUnexecutableGarbageBinary()
        defer { layout.cleanup() }
        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin)

        await SpawnGate.shared.run {
            do {
                _ = try installer.connect(force: false, translocated: false, inDownloads: false)
                Issue.record("預期 throw .hookUnconfirmed，卻成功了")
            } catch InstallerFailure.hookUnconfirmed(let stamp) {
                #expect(!stamp.isEmpty)
            } catch {
                Issue.record("預期 .hookUnconfirmed，實際是 \(error)")
            }
        }
    }

    /// 逾時與 spawn 丟錯是**不同**的程式路徑（S2-11：不得共用一種寫回值背後的成因），
    /// 但兩者目前都寫回同一個 `.hookUnconfirmed`——這條證明「逾時」這條路徑本身能被
    /// 觸發，不是只有 spawn-throws 那一半在動。
    ///
    /// **T06b**：原本靠「真的等超過 2 秒」來驗上限存在，但那讓正常路徑在全套件並行時
    /// 反過來偶發誤判（4 次全量有 2 次紅）。改成注入很小的上限——行程仍然是真的在跑
    /// （`makeWithSlowHookBinary`），只是不必等 2 秒，也不再依賴「機器夠慢」這個不可控前提。
    @Test("行程真的在跑但超過有界等待仍未結束 → throw .hookUnconfirmed(stamp:)（逾時，S2-11 的另一半）")
    func connectThrowsUnconfirmedOnTimeout() async throws {
        let layout = try InstallerFixture.makeWithSlowHookBinary()
        defer { layout.cleanup() }
        let installer = InstallerFixture.installer(claudeHome: layout.claudeHome, bundlePluginURL: layout.bundlePlugin,
                                  verificationTimeout: 0.05)

        await SpawnGate.shared.run {
            do {
                _ = try installer.connect(force: false, translocated: false, inDownloads: false)
                Issue.record("預期 throw .hookUnconfirmed（逾時），卻成功了")
            } catch InstallerFailure.hookUnconfirmed(let stamp) {
                #expect(!stamp.isEmpty)
            } catch {
                Issue.record("預期 .hookUnconfirmed，實際是 \(error)")
            }
        }
    }
}
