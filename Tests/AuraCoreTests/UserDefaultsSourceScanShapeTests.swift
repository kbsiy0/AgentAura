import Testing
import Foundation

/// T01 必辦⑤的自我測試：驗證 `UserDefaultsSourceScan` 真的區分得出「實際用了
/// `UserDefaults`」與「只在註解裡提到這個詞、沒有標點」。**這條合理地是 GREEN**——
/// 驗的是掃描機制本身對合成 probe 的行為，不是還沒寫的 `Sources/AuraHookFile/Installer.swift`。
@Suite("UserDefaultsSourceScan 自我驗證")
struct UserDefaultsSourceScanShapeTests {

    @Test("正向對照：真的用了 UserDefaults.standard 會被抓到")
    func catchesRealUsage() throws {
        try Gate.withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("Probe.swift")
            try """
                import Foundation
                enum Probe {
                    static func read() -> String? { UserDefaults.standard.string(forKey: "x") }
                }
                """.write(to: probe, atomically: true, encoding: .utf8)
            let (scanned, hits) = try UserDefaultsSourceScan.scan(under: dir)
            #expect(scanned == 1, "防空跑：應讀到 1 個 .swift")
            #expect(!hits.isEmpty, "掃描沒抓到 probe 裡真的用了 UserDefaults.standard —— 解析壞了會讓所有東西看起來都乾淨")
        }
    }

    @Test("正向對照：UserDefaults(suiteName:) 建構式也會被抓到")
    func catchesConstructorUsage() throws {
        try Gate.withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("Probe.swift")
            try """
                import Foundation
                enum Probe {
                    static let d = UserDefaults(suiteName: "test")
                }
                """.write(to: probe, atomically: true, encoding: .utf8)
            let (_, hits) = try UserDefaultsSourceScan.scan(under: dir)
            #expect(!hits.isEmpty, "掃描沒抓到 probe 裡的 UserDefaults(suiteName:) 建構式")
        }
    }

    /// 這是實測踩過的那個 bug 的回歸對照：裸字樣掃描會被這種註解命中，
    /// 帶標點的版本不會——證明選這個樣式不是隨意的。
    @Test("負對照：只在註解裡提到 UserDefaults（沒有標點）不會被抓到")
    func doesNotFlagBareMentionInComment() throws {
        try Gate.withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("Probe.swift")
            let source = """
                import Foundation
                // 這一層不得碰 UserDefaults —— 憑證讀寫留在 app 層的 store
                enum Probe {
                    static func noop() {}
                }
                """
            try source.write(to: probe, atomically: true, encoding: .utf8)

            // 先證明「裸字樣」掃描（沒有標點要求）確實會誤判——這是要修的那個 bug。
            #expect(source.contains("UserDefaults"), "前提：註解裡確實提到這個詞")
            #expect(!source.contains("UserDefaults(") && !source.contains("UserDefaults."),
                    "前提：註解裡沒有標點形式")

            let (scanned, hits) = try UserDefaultsSourceScan.scan(under: dir)
            #expect(scanned == 1)
            #expect(hits.isEmpty, """
                帶標點的掃描誤判了純註解提及，實際命中 \(hits.map(\.lastPathComponent)) ——
                回到了裸字樣掃描會被註解命中的老問題
                """)
        }
    }

    @Test("檔數防空跑：讀不到任何 .swift 檔時，呼叫端必須能觀察到 scanned == 0")
    func fileCountGuardsAgainstEmptyRun() throws {
        try Gate.withTemporaryDirectory { dir in
            let (scanned, hits) = try UserDefaultsSourceScan.scan(under: dir)
            #expect(scanned == 0, "空目錄應回報 0 個檔，讓呼叫端的防空跑斷言抓到「這次沒掃到東西」")
            #expect(hits.isEmpty)
        }
    }
}
