import Testing
import Foundation

/// T10b（change `app-shell`）：關掉「exec 驗證逾時 flake」這個**類別**，不是修單一測試。
///
/// 病灶：`Installer.verificationTimeout` 生產預設 2 秒。測試若直接裸建構 `Installer`
/// （帶 `claudeHome:` 參數），`connect()` 會真的 spawn `aura-hook`；全套件並行時搶行程資源，
/// 2 秒偶發不夠 → 正常路徑被誤判成 `.hookUnconfirmed`（實測 `InstallerPathScopeTests`
/// `failed after 2.051 seconds`，2.051 秒就是撞到 2 秒上限）。
///
/// 這是同一個病第三次復發：T06b（`InstallerTests`／`InstallerExecVerificationTests`）與 T08
/// （新增一批 exec 測試時在 4＋1 處補 `verificationTimeout: 5`）都各自補了洞，但沒有堵住
/// 「新增測試忘了補」這個入口——`InstallerPathScopeTests`／`InstallerClobberTests` 從來沒補過。
///
/// 修法：`InstallerFixture`／`AppInstallerFixture` 各長出一個 `installer(claudeHome:
/// bundlePluginURL:…)` 工廠（預設 `verificationTimeout: 5`）。這條 gate 鎖住入口本身：
/// 除了那兩個 fixture 檔，`Tests/AuraCoreTests/` 與 `Tests/AgentAuraAppTests/` 底下
/// 不准裸建構 `Installer`——新測試想繞過工廠、想省事直接建構，會在這裡紅。
///
/// **允許清單是它自己的逃生門**（review 教訓：R5 的 `nonMenuKinds` 同一個形狀——手寫
/// 允許清單一旦能被隨手加大，gate 就名存實亡）。兩件事一起做，缺一不可：
/// 1. 搜尋字面用字串**串接**組出來，這份 gate 檔自己的原始碼就不含完整字面，不會
///    撞到自己——允許清單因此可以縮到**只剩兩個真正的工廠實作檔**，不必為 gate 自己開口子。
/// 2. 允許清單本身**釘死並斷言相等**（`allowedFilesArePinned`）——往裡面加第三個檔名
///    這件事本身要能被看見、變紅，不能無聲無息地擴大。
@Suite("Installer 建構點必須經過 fixture 工廠（T10b）")
struct InstallerConstructionSourceScanTests {

    /// 搜尋字面**故意用字串串接組出來，不寫成一個完整的 Swift 字串常量**——這樣這份
    /// gate 檔自己的原始碼（含所有 doc comment／字串）都不含完整的那串連續字元，
    /// 「掃到自己」的問題因此根本不存在，允許清單不必為它開特例。
    private static let needle = "Installer(" + "claudeHome:"

    /// **釘死的允許清單**：只有這兩個工廠實作檔准許出現上面那個字面建構呼叫。
    /// `allowedFilesArePinned` 斷言這個集合恰好等於這兩個檔名——多一個字都要紅。
    static let allowedFiles: Set<String> = [
        "InstallerFixture.swift",
        "AppInstallerFixture.swift",
    ]

    /// 回傳「實際讀成功的檔數」與含搜尋字面的 (檔案, 命中次數) 清單（排除 `allowedFiles`）。
    /// 同一個 reader 供正式斷言與正向對照共用——讀不到檔一律 throw，不是安靜回空
    /// （review 教訓：`try?` 吞掉讀取失敗會讓真違規跟著消失）。
    static func scan(under directory: URL) throws -> (scanned: Int, hits: [(URL, Int)]) {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw Gate.GateFailure("列不出目錄：\(directory.path)")
        }
        let files = e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        var hits: [(URL, Int)] = []
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)   // 讀不到 → 大聲紅，不是乾淨
            guard !allowedFiles.contains(url.lastPathComponent) else { continue }
            let count = text.components(separatedBy: needle).count - 1
            if count > 0 { hits.append((url, count)) }
        }
        return (files.count, hits)
    }

    @Test("Tests/AuraCoreTests 與 Tests/AgentAuraAppTests 底下，除了兩個 fixture 檔，沒有任何檔案直接裸建構 Installer 的 claudeHome 建構子")
    func noDirectInstallerConstructionOutsideFixtures() throws {
        let roots = [
            Gate.repoRoot().appendingPathComponent("Tests/AuraCoreTests"),
            Gate.repoRoot().appendingPathComponent("Tests/AgentAuraAppTests"),
        ]
        var totalScanned = 0
        var allHits: [(URL, Int)] = []
        for root in roots {
            let (scanned, hits) = try Self.scan(under: root)
            totalScanned += scanned
            allHits += hits
        }
        #expect(totalScanned >= 90, "只讀到 \(totalScanned) 個 .swift —— gate 不能空跑")
        #expect(allHits.isEmpty, """
            以下檔案仍直接裸建構 \(Self.needle)，繞過了 verificationTimeout: 5 的 fixture 工廠：
            \(allHits.map { "\($0.0.lastPathComponent)×\($0.1)" }.sorted().joined(separator: "、"))
            ——這正是 exec 驗證逾時 flake 的入口（生產預設 2 秒，全套件並行下會偶發撞到）。
            改用 InstallerFixture.installer(claudeHome:bundlePluginURL:…) /
            AppInstallerFixture.installer(claudeHome:bundlePluginURL:…)。
            """)
    }

    /// 正向對照：暫存目錄放一個真的含建構呼叫的 probe，證明掃描抓得到——不是解析壞掉時
    /// 安靜放行一切。probe 內容同樣用 `needle` 串接寫入，**絕不寫進 `Tests/` 或 `Sources/`**。
    @Test("正向對照：掃描函式對真違規會紅")
    func scanCatchesRealViolation() throws {
        try Gate.withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("Probe.swift")
            let content = "let installer = " + Self.needle
                + " URL(fileURLWithPath: \"/tmp\"), bundlePluginURL: URL(fileURLWithPath: \"/tmp\"))"
            try content.write(to: probe, atomically: true, encoding: .utf8)
            let (scanned, hits) = try Self.scan(under: dir)
            #expect(scanned == 1)
            #expect(!hits.isEmpty, "掃描函式沒抓到 probe 裡的建構呼叫 —— 解析壞了會讓所有東西看起來都乾淨")
        }
    }

    /// 正向對照的另一半：同名但屬於 `allowedFiles` 的檔案不該被計入 hits——
    /// 沒有這條，「工廠本身合法」跟「排除清單失效」兩種情況會看起來一樣綠。
    @Test("正向對照：allowedFiles 清單裡的檔名即使含違規字樣也不計入 hits")
    func allowedFilesAreExcludedFromHits() throws {
        try Gate.withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("InstallerFixture.swift")
            let content = "let installer = " + Self.needle
                + " URL(fileURLWithPath: \"/tmp\"), bundlePluginURL: URL(fileURLWithPath: \"/tmp\"))"
            try content.write(to: probe, atomically: true, encoding: .utf8)
            let (_, hits) = try Self.scan(under: dir)
            #expect(hits.isEmpty, "allowedFiles 裡的檔名（InstallerFixture.swift）不該被算進 hits")
        }
    }

    /// **逃生門守衛**：`allowedFiles` 本身不是自由心證的清單——它恰好等於這兩個工廠檔名，
    /// 一個字都不能多。少了這條，未來有人想省事把自己的測試檔名塞進允許清單、繞過整條
    /// gate，`scan()` 會安靜配合（R5 `nonMenuKinds` 同一個形狀：手寫清單可以被隨手加大）。
    @Test("釘死允許清單：只准恰好是兩個工廠實作檔，多一個都要紅（逃生門不能被偷偷加大）")
    func allowedFilesArePinned() throws {
        #expect(Self.allowedFiles == ["InstallerFixture.swift", "AppInstallerFixture.swift"], """
            allowedFiles 被改動了，實際：\(Self.allowedFiles.sorted())。
            這份清單只准手動改這份原始碼並經過 review，不准被悄悄加大來放行新的裸建構違規。
            """)
    }
}
