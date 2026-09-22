import Testing
import Foundation

/// G12（spec §6.2／§6.3，T08）：`acknowledgeAllHasExactlyOneCallSite`——`Sources/AgentAuraApp/`
/// 內樣式 `.acknowledgeAll(`（**帶點**，排除宣告與註解裡的反引號提及）恰好 1 個命中，
/// 且命中在 `AppDelegate+Lifecycle.swift`（T13a：`applicationDidFinishLaunching` 連同它裡面的
/// `status.onClose` 閉包一起做零行為變更的純搬移，唯一呼叫點跟著搬過去——性質沒變，
/// 還是「acknowledge 只准在 onClose 發生」這件事，只是物理檔名跟著移動）。
/// CLAUDE.md invariant：「acknowledge 只在 onClose」——
/// 少了這條，往任何地方（`connect`／`disconnect`／`onOpen`）補一次呼叫都不會被抓到。
///
/// N4（r2 教訓）：掃 `Sources/` 整個對 `acknowledgeAll(`（不帶點）會命中宣告本身
/// （`PipelineGraph.acknowledgeAll()`／`SessionRegistry.acknowledgeAll()`）＋
/// `PipelineGraph` 內部合法呼叫 `registry.acknowledgeAll()`——照字面寫 born-red。
/// 帶點 ＋ 只掃 `AgentAuraApp` 才是這條 gate 真正該問的範圍。
@Suite("acknowledgeAll 唯一呼叫點來源掃描（G12）")
struct AcknowledgeCallSiteSourceScanTests {

    /// 回傳「實際讀成功的檔數」與含 `.acknowledgeAll(` 字樣的 (檔案, 命中次數) 清單。
    /// 同一個 reader 供正式斷言與正向對照共用（防空跑：讀不到檔一律 throw，不是安靜回空）。
    static func scan(under directory: URL) throws -> (scanned: Int, hits: [(URL, Int)]) {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw Gate.GateFailure("列不出目錄：\(directory.path)")
        }
        let files = e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        var hits: [(URL, Int)] = []
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)   // 讀不到 → 大聲紅，不是乾淨
            let count = text.components(separatedBy: ".acknowledgeAll(").count - 1
            if count > 0 { hits.append((url, count)) }
        }
        return (files.count, hits)
    }

    @Test("Sources/AgentAuraApp/ 內 .acknowledgeAll( 恰好 1 個命中，且在 AppDelegate+Lifecycle.swift")
    func exactlyOneCallSiteInAppDelegate() throws {
        let root = Gate.repoRoot().appendingPathComponent("Sources/AgentAuraApp")
        let (scanned, hits) = try Self.scan(under: root)
        #expect(scanned >= 15, "Sources/AgentAuraApp 只讀到 \(scanned) 個 .swift —— gate 不能空跑")

        let totalHits = hits.reduce(0) { $0 + $1.1 }
        #expect(totalHits == 1, """
            Sources/AgentAuraApp/ 內 .acknowledgeAll( 應恰好 1 個命中，實際 \(totalHits) 個：
            \(hits.map { "\($0.0.lastPathComponent)×\($0.1)" }.sorted())
            ——acknowledge 只准在 onClose 發生（CLAUDE.md invariant），多一個呼叫點就是
            「已結束但未確認的尾巴」提早消失的 bug。
            """)
        #expect(hits.first?.0.lastPathComponent == "AppDelegate+Lifecycle.swift", """
            唯一的命中應該在 AppDelegate+Lifecycle.swift（T13a 純搬移之後），實際在 \(hits.map(\.0.lastPathComponent))
            """)
    }

    /// 正向對照（沿用 G-src 既有慣例）：暫存目錄放一個含假呼叫的 probe，
    /// 同一個 reader 必須抓到——沒有這條，上面「== 1」在解析壞掉時也可能安靜綠或安靜紅。
    @Test("正向對照：暫存目錄放一個含 .acknowledgeAll( 呼叫的 probe，掃描必須抓到且不誤判宣告／註解")
    func scanCatchesRealCallSiteButNotDeclarationOrComment() throws {
        try Gate.withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("Probe.swift")
            try """
                // 註解裡提到 `acknowledgeAll()`（反引號，不帶點）不該算命中
                struct Probe {
                    func acknowledgeAll() { }        // 宣告本身（沒有前導 `.`）不該算命中
                    func trigger(_ x: Probe) { x.acknowledgeAll() }   // 真呼叫——帶點，應該算命中
                }
                """.write(to: probe, atomically: true, encoding: .utf8)
            let (scanned, hits) = try Self.scan(under: dir)
            #expect(scanned == 1)
            let totalHits = hits.reduce(0) { $0 + $1.1 }
            #expect(totalHits == 1, """
                掃描應恰好抓到 1 個真呼叫（x.acknowledgeAll()），不誤判宣告或註解裡的反引號提及，
                實際 \(totalHits)
                """)
        }
    }
}
