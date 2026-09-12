import Testing
import Foundation

/// A8（T11 commit3）：D-a 把「重設」從圖例列搬進 Options（「重設顏色」列），理由是
/// 「一年按一次卻永遠佔一格且多半是灰的」——但舊的那顆一直沒拿掉，兩處重複存在
/// （persona 從截圖抓到的，不在原本的八條清單裡）。這條鎖住入口本身：
/// `LegendRowView.swift` 不得再出現 `.resetColors`，下一個人想「順手」加回來會在這裡紅。
@Suite("圖例列不得重複「重設顏色」（A8，T11 commit3）")
struct LegendRowNoResetSourceScanTests {
    // 串接組出來，避免這份 gate 檔自己的原始碼（doc comment）撞到自己。
    private static let needle = "." + "resetColors"

    static func scan(file: URL) throws -> Bool {
        let text = try String(contentsOf: file, encoding: .utf8)   // 讀不到 → 大聲紅，不是安靜放行
        return text.contains(needle)
    }

    @Test("LegendRowView.swift 不得出現 .resetColors")
    func legendRowViewDoesNotReferenceResetColors() throws {
        let file = Gate.repoRoot().appendingPathComponent("Sources/AgentAuraApp/LegendRowView.swift")
        #expect(FileManager.default.fileExists(atPath: file.path), "掃描目標檔案不存在：\(file.path) —— gate 不能空跑")
        let hit = try Self.scan(file: file)
        #expect(!hit, """
            LegendRowView.swift 出現了 \(Self.needle) —— 「重設」又被加回圖例列了，
            跟 Options 裡的「重設顏色」重複（D-a：搬過去的理由是它一年按一次卻永遠佔一格）。
            """)
    }

    @Test("正向對照：掃描函式對真違規會紅")
    func scanCatchesRealViolation() throws {
        try Gate.withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("Probe.swift")
            try ("Button(\"重設\") { onAction(" + Self.needle + ") }").write(to: probe, atomically: true, encoding: .utf8)
            #expect(try Self.scan(file: probe), "掃描函式沒抓到 probe 裡的違規字樣")
        }
    }
}
