import Testing
import Foundation

/// `verificationStoreIsInjected`（spec §6.2／§6.3）——**掃描那半**（T07 交付）：
/// `Sources/AuraHookFile/` 不得出現 `UserDefaults(`／`UserDefaults.`（R1——`Installer` 是
/// `Sendable`，`UserDefaults` 的 `Sendable` conformance 在 Swift 6 下 unavailable，憑證
/// I/O 必須留在 app 層的 `HookVerificationStore`，比照 `PaletteStore`）。
///
/// **「生產注入的不是 fake」那半留給 T08**：composition root（`AppDelegate`）要接上
/// `HookVerificationStore` 之後才驗得到「注入的不是 fake」，T07 只交付 store 這個元件
/// 本身，尚未接線。
@Suite("HookVerificationStore 注入來源掃描（verificationStoreIsInjected，掃描半）")
struct HookVerificationStoreSourceScanTests {

    @Test("Sources/AuraHookFile/ 不得出現 UserDefaults( 或 UserDefaults.（帶標點，排除純註解提及）")
    func auraHookFileNeverTouchesUserDefaults() throws {
        let root = Gate.repoRoot().appendingPathComponent("Sources/AuraHookFile")
        let (scanned, hits) = try UserDefaultsSourceScan.scan(under: root)
        #expect(scanned >= 3, "Sources/AuraHookFile 只讀到 \(scanned) 個 .swift —— gate 不能空跑")
        #expect(hits.isEmpty, """
            以下檔案在 AuraHookFile 出現 UserDefaults( 或 UserDefaults.：
            \(hits.map(\.lastPathComponent).sorted())——R1：Sendable 的 Installer 不得碰 UserDefaults，
            憑證 I/O 必須留在 app 層的 HookVerificationStore
            """)
    }

    /// 正向對照（沿用 G12 的既有慣例）：暫存目錄放一個真的用了 `UserDefaults.standard` 的
    /// probe，同一個 reader 必須抓到——沒有這條，上面那條「hits.isEmpty」在解析壞掉時
    /// 也會安靜綠。
    @Test("正向對照：暫存目錄放一個真的用了 UserDefaults.standard 的 probe，掃描必須抓到")
    func scanCatchesRealUsageInTemporaryProbe() throws {
        try Gate.withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("Probe.swift")
            try """
                import Foundation
                enum Probe {
                    static func read() -> String? { UserDefaults.standard.string(forKey: "x") }
                }
                """.write(to: probe, atomically: true, encoding: .utf8)
            let (scanned, hits) = try UserDefaultsSourceScan.scan(under: dir)
            #expect(scanned == 1)
            #expect(!hits.isEmpty, """
                掃描沒抓到 probe 裡真的用了 UserDefaults.standard —— 解析壞了會讓
                AuraHookFile 的檢查看起來永遠乾淨
                """)
        }
    }
}
