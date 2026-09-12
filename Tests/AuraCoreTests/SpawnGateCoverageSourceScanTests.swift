import Testing
import Foundation

/// T10b（team-lead 診斷）：鎖住「新測試會真的 spawn 一個行程，卻忘了經過 `SpawnGate`」
/// 這個入口。病灶見 `Tests/AuraCoreTests/Support/SpawnGate.swift` 的文件——swift-testing
/// 預設跨 suite 並行，沒有全套件唯一的序列化點，機器會被自己的測試灌滿。
///
/// **範圍是誠實的、不是完整的**：這條 gate 只抓得到**直接**在測試檔字面上呼叫
/// `installer.connect`／`installer.replaceExternalMount`，或直接組出「餵 aura-hook 那個
/// 環境變數」的檔案——這是本專案目前兩種「測試碼自己直接觸發 spawn」的寫法（各種
/// `Installer` 測試的 `connect()`／`replaceExternalMount()`；`AuraHookCLITests` 與其他
/// 幾個黑箱測試直接用 `Process()` 打 aura-hook 二進位）。
///
/// 原本想拿裸 `Process(` 當第三個觸發字面，**實測是錯的**：套件裡另外還有 7 個檔案用
/// `Process()` 呼叫 `swiftc`／`lipo`／`claude` 之類完全無關的工具（`IsolationTests`／
/// `Gate.swift`／`PluginWiringTests`／`LivenessTests` 等），拿裸 `Process(` 當觸發字面會
/// 誤判這些檔案也要接 SpawnGate。改用「餵給 aura-hook 那個環境變數的鍵名」當第三個觸發
/// 字面——本專案目前每一處真的 spawn aura-hook 的地方都會設這個環境變數（見
/// `Sources/AuraHookFile/Installer+ExecVerification.swift` 與 `AuraHookCLITests` 的
/// `environment.merging(...)`），而 swiftc／lipo／claude 這些呼叫都不會，精準命中
/// 「真的在 spawn aura-hook」這個類別。
///
/// **抓不到**透過 composition root **間接**觸發的 spawn（例如
/// `AppDelegate.applicationDidFinishLaunching` 內部的背景驗證、`onAction(.connect)`）——
/// 那一類目前只能靠人工比對 team-lead 指名的檔案清單（`AppDelegateVerificationLifecycleTests`／
/// `AppDelegateUnknownNeverTerminalTests`／`AppDelegatePanelActionsWiredTests`），沒有簡單
/// 的字面樣式能可靠涵蓋，誠實承認比假裝涵蓋更好（同一個 change 裡
/// `InstallerConstructionSourceScanTests` 也有一樣的性質限制）。
@Suite("Spawn 一律經過 SpawnGate（T10b）")
struct SpawnGateCoverageSourceScanTests {

    /// 觸發字面**故意用字串串接組出來**，這份 gate 檔自己的原始碼因此不含完整的觸發字面，
    /// 不會把自己也判定成「需要 SpawnGate」——同一招沿用
    /// `InstallerConstructionSourceScanTests` 的自我指涉解法。
    private static let envNeedle = "AGENTAURA" + "_ROOT"
    private static let connectNeedle = "installer" + ".connect("
    private static let replaceNeedle = "installer" + ".replaceExternalMount("
    private static let triggers = [envNeedle, connectNeedle, replaceNeedle]
    private static let requiredMarker = "SpawnGate"

    /// 回傳「實際讀成功的檔數」與「含觸發字面、但沒有同時出現 SpawnGate 字樣」的違規檔案。
    /// 讀不到檔一律 throw，不是安靜回空。
    static func scan(under directory: URL) throws -> (scanned: Int, violations: [URL]) {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw Gate.GateFailure("列不出目錄：\(directory.path)")
        }
        let files = e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        var violations: [URL] = []
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)   // 讀不到 → 大聲紅，不是乾淨
            guard triggers.contains(where: { text.contains($0) }) else { continue }
            if !text.contains(requiredMarker) { violations.append(url) }
        }
        return (files.count, violations)
    }

    @Test("Tests/AuraCoreTests 與 Tests/AgentAuraAppTests 底下，任何直接觸發 spawn 的檔案都必須看得到 SpawnGate")
    func everySpawnTriggerFileMentionsSpawnGate() throws {
        let roots = [
            Gate.repoRoot().appendingPathComponent("Tests/AuraCoreTests"),
            Gate.repoRoot().appendingPathComponent("Tests/AgentAuraAppTests"),
        ]
        var totalScanned = 0
        var allViolations: [URL] = []
        for root in roots {
            let (scanned, violations) = try Self.scan(under: root)
            totalScanned += scanned
            allViolations += violations
        }
        #expect(totalScanned >= 90, "只讀到 \(totalScanned) 個 .swift —— gate 不能空跑")
        #expect(allViolations.isEmpty, """
            以下檔案直接呼叫 installer.connect／installer.replaceExternalMount，或直接組出
            餵給 aura-hook 的環境變數，卻沒有經過 SpawnGate：
            \(allViolations.map(\.lastPathComponent).sorted())
            ——全套件並行時會跟其他 spawn 搶行程資源，正是這個 change 要關掉的 flake 類別。
            """)
    }

    /// 正向對照：暫存目錄放一個真的含觸發字面、但沒有 SpawnGate 字樣的 probe，證明掃描抓得到。
    @Test("正向對照：掃描函式對「有觸發字面但沒有 SpawnGate」的真違規會紅")
    func scanCatchesRealViolation() throws {
        try Gate.withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("Probe.swift")
            let content = "let installer = Foo()\nlet stamp = try " + Self.connectNeedle
                + "force: false, translocated: false, inDownloads: false)\n"
            try content.write(to: probe, atomically: true, encoding: .utf8)
            let (scanned, violations) = try Self.scan(under: dir)
            #expect(scanned == 1)
            #expect(!violations.isEmpty, "掃描函式沒抓到 probe 裡「有觸發字面卻沒有 SpawnGate」——解析壞了會讓所有東西看起來都乾淨")
        }
    }

    /// 正向對照的另一半：同樣含觸發字面，但**也**提到 SpawnGate 的檔案不該被判違規——
    /// 沒有這條，「真的接了閘門」跟「掃描邏輯失效」兩種情況會看起來一樣綠。
    @Test("正向對照：觸發字面＋SpawnGate 字樣同時出現時不算違規")
    func scanDoesNotFlagFilesThatMentionSpawnGate() throws {
        try Gate.withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("Probe.swift")
            let content = "await SpawnGate.shared.run {\n    _ = try " + Self.connectNeedle
                + "force: false, translocated: false, inDownloads: false)\n}\n"
            try content.write(to: probe, atomically: true, encoding: .utf8)
            let (_, violations) = try Self.scan(under: dir)
            #expect(violations.isEmpty, "含 SpawnGate 字樣的檔案不該被判違規")
        }
    }
}
