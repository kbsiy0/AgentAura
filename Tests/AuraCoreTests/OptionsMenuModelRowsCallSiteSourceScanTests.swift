import Testing
import Foundation

/// T08b（T07 review 回頭補的裂縫，比照 `SessionStateAgentSourceScanTests` 的形狀）：
/// `OptionsSectionView.swift` 曾經暫時硬編 `codex: .unavailable, codexPathRejection: nil`
/// （那時 `PanelModel` 還沒有這兩個欄位）——那個 stub 失效是**靜默的**：`.unavailable`
/// 正好是所有既有測試期待的值，854 條全綠而 Codex 的 Options 列永遠不出現。
/// 這條 gate 守的就是這個方向：`Sources/` 底下 `OptionsMenuModel.rows(` 的生產呼叫恰
/// 一處，且那一處**不得**是字面 `.unavailable`／`nil`——必須讀 `model.codex`／
/// `model.codexPathRejection`。
@Suite("OptionsMenuModel.rows( 生產呼叫點必須傳 model 的 codex 狀態")
struct OptionsMenuModelRowsCallSiteSourceScanTests {

    @Test("Sources/ 底下 OptionsMenuModel.rows( 恰有一處呼叫，且未寫死 codex: .unavailable／codexPathRejection: nil")
    func productionCallSitePassesModelCodexState() throws {
        let root = Gate.repoRoot().appendingPathComponent("Sources")
        let (scanned, occurrences) = try OptionsMenuModelRowsCallSiteScan.scan(under: root)
        #expect(scanned >= 3, "Sources/ 只讀到 \(scanned) 個 .swift —— gate 不能空跑")
        #expect(occurrences.count == 1, """
            Sources/ 底下 OptionsMenuModel.rows( 的呼叫應恰為 1 處（目前只有
            OptionsSectionView.rows），實際找到 \(occurrences.count) 處：
            \(occurrences.map { $0.file.lastPathComponent })。
            新增第二個生產呼叫點時必須重新檢視這條 gate 的斷言方式（例如逐一檢查每一處）。
            """)
        if let only = occurrences.first {
            #expect(!only.block.contains("codex: .unavailable"), """
                \(only.file.lastPathComponent) 裡的 OptionsMenuModel.rows( 呼叫把 codex
                寫死成 .unavailable——那正是所有既有測試期待的值，全套件會照樣全綠，
                而 Codex 的 Options 列永遠不出現（tested≠wired）。呼叫區塊：
                \(only.block)
                """)
            #expect(!only.block.contains("codexPathRejection: nil"), """
                \(only.file.lastPathComponent) 裡的 OptionsMenuModel.rows( 呼叫把
                codexPathRejection 寫死成 nil——`.connectedStalePath` 的「重新接上」按鈕
                會在路徑被拒時仍然畫出來（R-9 的守衛失效）。呼叫區塊：
                \(only.block)
                """)
        }
    }

    /// 正向對照（沿用 `SessionStateAgentSourceScanTests` 的既有慣例）：暫存目錄放兩個
    /// probe，一個寫死字面 stub、一個傳 model 的值，同一個 scanner 必須各自正確判斷——
    /// 沒有這條，上面「occurrences.count == 1」與「block 不含字面」在解析壞掉時也可能
    /// 安靜綠。
    @Test("正向對照：scanner 正確抓到多處呼叫，且逐一判斷有沒有寫死字面 stub")
    func scanCatchesMultipleCallSitesAndDistinguishesLiteralStub() throws {
        try Gate.withTemporaryDirectory { dir in
            let stubbed = dir.appendingPathComponent("StubbedProbe.swift")
            try """
                enum Probe {
                    static func makeRows() -> [OptionsRow] {
                        OptionsMenuModel.rows(install: .notConnected, launchAtLogin: nil,
                                              isDefaultPalette: true, systemReduceMotion: false,
                                              userReduceMotion: false, iconPlate: true,
                                              iconShape: .ledStrip, palette: .default,
                                              language: .english, codex: .unavailable,
                                              codexPathRejection: nil)
                    }
                }
                """.write(to: stubbed, atomically: true, encoding: .utf8)

            let wired = dir.appendingPathComponent("WiredProbe.swift")
            try """
                enum Probe2 {
                    static func makeRows(model: PanelModel) -> [OptionsRow] {
                        OptionsMenuModel.rows(install: model.install, launchAtLogin: model.launchAtLogin,
                                              isDefaultPalette: model.isDefaultPalette,
                                              systemReduceMotion: model.systemReduceMotion,
                                              userReduceMotion: model.userReduceMotion,
                                              iconPlate: model.iconPlate, iconShape: model.iconShape,
                                              palette: model.palette, language: model.language,
                                              codex: model.codex, codexPathRejection: model.codexPathRejection)
                    }
                }
                """.write(to: wired, atomically: true, encoding: .utf8)

            let (scanned, occurrences) = try OptionsMenuModelRowsCallSiteScan.scan(under: dir)
            #expect(scanned == 2, "解析沒抓到暫存目錄的兩個 probe 檔")
            #expect(occurrences.count == 2, """
                scanner 沒有抓到兩處 OptionsMenuModel.rows( 呼叫——解析壞了會讓生產端的
                「恰為 1 處」檢查在漏抓時也安靜綠
                """)
            let stubbedCount = occurrences.filter { $0.block.contains("codex: .unavailable") }.count
            #expect(stubbedCount == 1, """
                scanner 應該只判定一個 probe 寫死 codex: .unavailable，實際 \(stubbedCount) 個——
                解析壞了會讓「block.contains 字面」失去分辨力
                """)
        }
    }
}
