import Testing
import Foundation

/// D-5(3)：`Sources/` 底下任何字串字面含中日韓統一表意文字，都必須住在字串表
/// （`L10n*.swift`）裡，不得散在其他生產檔——這條擋的是「新功能又寫死一句中文」。
///
/// T26／T27／T28-T29 分批把 ~107 個字面全部搬完（T29 收尾 `AgentAuraApp` 最後 7 個檔），
/// `pendingMigrationFiles` 因此清空——`noStrayLiteralOutsideAllowlist` 從這裡起才是
/// **真正生效**的 gate（在那之前它只擋「新增的中文寫死」，清單內的舊帳看不到）。
@Suite("D-5(3)：Sources/ 的中文字面必須都在字串表裡")
struct L10nStrayLiteralSourceScanTests {

    /// T29：`AgentAuraApp` 最後 7 個檔搬完，清單清空（見下方 `pendingMigrationFilesArePinned`）。
    /// 型別留著（不是直接砍掉常數）是為了 `scan(under:allowlist:)` 的預設值＋
    /// `allowlistedFileIsSkipped` 說明清單機制本身沒有跟著搬遷進度一起被拔掉。
    static let pendingMigrationFiles: Set<String> = []

    /// 字串表本體自己一定含中文字面（它就是翻譯內容住的地方）——依檔名前綴排除，
    /// 不需要另外列進允許清單（允許清單語意是「尚未搬遷」，字串表不適用這個語意）。
    ///
    /// `allowlist` 預設走真正的 `pendingMigrationFiles`（目前是空集合，即真正的 gate）；
    /// `allowlistedFileIsSkipped` 覆寫一個合成的假想清單，驗證「機制本身」在清單非空時
    /// 仍然生效，不依賴目前搬遷進度是否還留著任何檔名。
    static func scan(under directory: URL, allowlist: Set<String> = pendingMigrationFiles) throws
        -> (scanned: Int, hits: [String]) {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw Gate.GateFailure("列不出目錄：\(directory.path)")
        }
        let files = e.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && !$0.lastPathComponent.hasPrefix("L10n") }
        var hits: [String] = []
        for url in files {
            guard !allowlist.contains(url.lastPathComponent) else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)   // 讀不到 → 大聲紅，不是乾淨
            if L10nLiteralScan.fileHasCJKStringLiteral(text) { hits.append(url.lastPathComponent) }
        }
        return (files.count, hits)
    }

    @Test("Sources/ 底下，允許清單以外的檔案不得有中文字串字面")
    func noStrayLiteralOutsideAllowlist() throws {
        let dir = Gate.repoRoot().appendingPathComponent("Sources")
        let (scanned, hits) = try Self.scan(under: dir)
        #expect(scanned >= 50, "只掃到 \(scanned) 個非 L10n .swift —— gate 不能空跑")
        #expect(hits.isEmpty, """
            以下檔案（不在暫時允許清單裡）出現中文字串字面，應該搬進 L10n*.swift：
            \(hits.sorted())
            """)
    }

    @Test("正向對照：允許清單以外新增中文字面會被抓到")
    func scanCatchesNewViolationOutsideAllowlist() throws {
        try Gate.withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("NotYetMigrated.swift")
            try "let x = \"這是新寫死的中文\"\n".write(to: probe, atomically: true, encoding: .utf8)
            let (_, hits) = try Self.scan(under: dir)
            #expect(hits == ["NotYetMigrated.swift"], "掃描沒抓到允許清單外的新違規")
        }
    }

    /// T29：`pendingMigrationFiles` 搬完之後是空集合，這條負對照因此改用一個明確的
    /// 假想檔名，透過 `scan(under:allowlist:)` 的 `allowlist` 參數覆寫（不再從真正的
    /// `pendingMigrationFiles` 推導）——驗的是「allowlist 機制本身仍然生效」，跟「目前
    /// 真的還有檔案在清單裡」是搬遷完成前後兩件不同的事，機制本身不該因為進度歸零而
    /// 跟著失去覆蓋（想清楚了：不是直接刪掉這條，而是換一種不依賴進度的方式驗證它）。
    @Test("負對照：allowlist 裡的檔名即使含中文字面也不計入 hits")
    func allowlistedFileIsSkipped() throws {
        try Gate.withTemporaryDirectory { dir in
            let imaginaryFixtureName = "ImaginaryNotYetMigratedFixture.swift"
            let probe = dir.appendingPathComponent(imaginaryFixtureName)
            try "let x = \"還沒搬的中文\"\n".write(to: probe, atomically: true, encoding: .utf8)
            let (_, hits) = try Self.scan(under: dir, allowlist: [imaginaryFixtureName])
            #expect(hits.isEmpty, "allowlist 裡的檔名不該被算進 hits")
        }
    }

    @Test("負對照：L10n*.swift 前綴的檔案（字串表本體）不計入 hits，即使不在 allowlist 裡")
    func l10nCatalogFilesAreExcludedFromScanTarget() throws {
        try Gate.withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("L10nProbe.swift")
            try "let x = \"這是字串表本體的翻譯內容\"\n".write(to: probe, atomically: true, encoding: .utf8)
            let (scanned, hits) = try Self.scan(under: dir)
            #expect(scanned == 0, "L10n*.swift 不該被算進掃描對象，實際 scanned=\(scanned)")
            #expect(hits.isEmpty)
        }
    }

    /// 釘死允許清單——**只准縮小**，隨搬遷進度遞減；要放大得經過 review。
    /// 19 → 7（T27）→ 0（T29）：`AuraCore` 與 `AgentAuraApp` 的生產碼中文字面都已搬完，
    /// 清單現在是空集合——`noStrayLiteralOutsideAllowlist` 從這裡起才是真正生效的 gate，
    /// 不再只擋「新增的中文寫死」。
    @Test("釘死允許清單：搬遷完成，清單應為空集合")
    func pendingMigrationFilesArePinned() {
        #expect(Self.pendingMigrationFiles.isEmpty,
                "實際還有 \(Self.pendingMigrationFiles.count) 個：\(Self.pendingMigrationFiles.sorted())——T27／T29 應已搬完全部生產碼中文字面")
    }
}
