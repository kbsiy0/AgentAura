import Testing
import Foundation

/// spec `2026-09-09-m4-icon-form-design.md` §6：`appLayerNeverSwitchesOnIconAnimation`。
@Suite("App 層來源掃描")
struct AppLayerSourceScanTests {

    /// 回傳「實際讀成功的檔數」與含 `case .breathe` 或 `case .doubleBlink` 字樣的檔案清單。**參數化**：
    /// 正式斷言傳 `Sources/AgentAuraApp`，正向對照傳暫存目錄裡的 probe。
    ///
    /// review-t01-0203 I2：舊版把「讀不到檔」當成乾淨（`try?` → false），防呆的檔數又來自另一個函式——
    /// 真違規＋encoding 壞掉時三層保護全綠。現在讀不到就 **throw**，檔數由同一個 reader 回報。
    static func scanForAnimationSwitches(under directory: URL) throws -> (scanned: Int, hits: [URL]) {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return (0, [])
        }
        let files = e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        var hits: [URL] = []
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)      // 讀不到 → 大聲紅，不是乾淨
            if text.contains("case .breathe") || text.contains("case .doubleBlink") { hits.append(url) }
        }
        return (files.count, hits)
    }

    /// **T01 這條會紅**：`AnimationDriver.period(of:)`（與 `LEDStripView.alpha(for:phase:)`）
    /// 目前都還有這兩個 case，T03 把曲線知識搬進 `AnimationCurve` 後才綠——這是正確的紅。
    @Test("App 層不得對 IconAnimation 做 switch（曲線知識只准活在 AnimationCurve）")
    func appLayerNeverSwitchesOnIconAnimation() throws {
        let root = Gate.repoRoot().appendingPathComponent("Sources/AgentAuraApp")
        let (scanned, hits) = try Self.scanForAnimationSwitches(under: root)
        #expect(scanned >= 5, "同一個 reader 只讀到 \(scanned) 個 .swift —— gate 不能空跑")
        #expect(hits.isEmpty, """
            以下檔案仍對 IconAnimation 做 switch（曲線知識應搬進 AnimationCurve）：
            \(hits.map(\.lastPathComponent).sorted())
            """)
    }

    /// 正向對照：gate 真的抓得到違規。probe 放暫存目錄，**絕不寫進 `Sources/`**
    /// （會弄壞建置、中斷時留垃圾）。
    @Test("掃描函式對真違規會紅（正向對照）")
    func scanCatchesRealViolation() throws {
        try Gate.withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("Probe.swift")
            try "switch a {\ncase .breathe: break\ndefault: break\n}\n"
                .write(to: probe, atomically: true, encoding: .utf8)
            let (_, hits) = try Self.scanForAnimationSwitches(under: dir)
            #expect(!hits.isEmpty, "掃描函式沒抓到 probe 裡的 `case .breathe` —— 解析壞了會讓所有東西看起來都乾淨")
        }
    }

    /// **同語料、同 reader** 的正向錨點（review I2）：`Sources/AuraCore/AnimationCurve.swift` 就含
    /// `case .breathe`，而且跟 App 層一樣有中文註解。純 ASCII 的暫存 probe 抓得到，不代表真實碼抓得到
    /// （encoding 一改就全乾淨）。掃 AuraCore 必須**恰好**回報這一個檔。
    @Test("同 reader 掃 AuraCore 必須恰好抓到 AnimationCurve.swift（真語料的正向錨點）")
    func scanFindsTheOneLegitimateSwitchInCore() throws {
        let root = Gate.repoRoot().appendingPathComponent("Sources/AuraCore")
        let (scanned, hits) = try Self.scanForAnimationSwitches(under: root)
        #expect(scanned >= 10, "AuraCore 只讀到 \(scanned) 個 .swift")
        #expect(hits.map(\.lastPathComponent) == ["AnimationCurve.swift"], """
            掃 AuraCore 應恰好抓到 AnimationCurve.swift，實際 \(hits.map(\.lastPathComponent).sorted())。
            少了 = reader 讀真實碼失效（App 層的違規也會溜過）；多了 = 曲線知識長到別處去了。
            """)
    }
}
