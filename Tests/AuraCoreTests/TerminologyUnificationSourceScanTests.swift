import Testing
import Foundation

/// A6（T11 commit3）：persona 實測同一件事有三個名字——`help.html` 教「捷徑」、UI 說
/// 「掛載」、確認對話框說「連結」。統一成「掛載」（spec／CLAUDE.md 用的就是這個詞）。
///
/// T13（S1-4 PARTIAL 收尾）：persona r2 抓到掃描範圍本身有洞——`docs/INSTALL.md` 與
/// `Sources/AuraCore/InstallAffordance.swift`（healthLabel「連結解不開」，`targetUnresolvable`）
/// 都不在 A6 原本的兩個目錄裡，兩處都改成「掛載」之後仍然漏網。擴大成四個掃描目標：
/// `Resources/`、`Sources/AgentAuraApp/`（A6 原本兩個）＋ `Sources/AuraCore/`、
/// `docs/INSTALL.md`（T13 新增）。`docs/` 底下其餘檔案（歷史 plan／design 文件）刻意不掃——
/// 那些是決策紀錄，不是使用者看得到的介面文案，回頭改字會竄改歷史。
@Suite("掛載概念統一用「掛載」，不再有「捷徑」／「連結」（A6，T11 commit3）")
struct TerminologyUnificationSourceScanTests {
    // 串接組出來，這份 gate 檔自己的原始碼因此不含完整字面，不會撞到自己
    // （同 `InstallerConstructionSourceScanTests`／`SpawnGateCoverageSourceScanTests` 的解法）。
    private static let needles = ["捷" + "徑", "連" + "結"]

    /// 「連結成功」講的是編譯器 linker（`RunningBundle.swift` 的 `@_silgen_name` 綁定），
    /// 跟掛載概念無關——同一種誤判形狀見 `InstallerConstructionSourceScanTests` 的說明。
    static let allowedFiles: Set<String> = ["RunningBundle.swift"]

    static func scan(under directory: URL) throws -> (scanned: Int, hits: [(URL, String)]) {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw Gate.GateFailure("列不出目錄：\(directory.path)")
        }
        let files = e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" || $0.pathExtension == "html" }
        var hits: [(URL, String)] = []
        for url in files {
            guard !allowedFiles.contains(url.lastPathComponent) else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)   // 讀不到 → 大聲紅，不是安靜放行
            for needle in needles where text.contains(needle) {
                hits.append((url, needle))
            }
        }
        return (files.count, hits)
    }

    @Test("Resources/ 與 Sources/AgentAuraApp/ 底下不得出現「捷徑」或「連結」指掛載這個概念")
    func noShortcutOrLinkWording() throws {
        let helpDir = Gate.repoRoot().appendingPathComponent("Resources")
        let appDir = Gate.repoRoot().appendingPathComponent("Sources/AgentAuraApp")
        let (scannedHelp, hitsHelp) = try Self.scan(under: helpDir)
        let (scannedApp, hitsApp) = try Self.scan(under: appDir)
        #expect(scannedHelp >= 1, "Resources/ 下沒掃到任何 .html/.swift —— gate 不能空跑")
        #expect(scannedApp >= 15, "Sources/AgentAuraApp/ 只讀到 \(scannedApp) 個檔 —— gate 不能空跑")

        let allHits = hitsHelp + hitsApp
        #expect(allHits.isEmpty, """
            以下檔案仍出現「捷徑」或「連結」指掛載這個概念，統一用「掛載」：
            \(allHits.map { "\($0.0.lastPathComponent)（\($0.1)）" }.sorted().joined(separator: "、"))
            """)
    }

    /// T13：`docs/INSTALL.md` 是單一檔案，直接讀比對；`Sources/AuraCore/` 沿用既有
    /// `scan(under:)`（全是 `.swift`，不需要新的檔案類型過濾）。
    @Test("T13 擴大範圍：docs/INSTALL.md 與 Sources/AuraCore/ 底下也不得出現「捷徑」或「連結」")
    func noShortcutOrLinkWordingInExpandedScope() throws {
        let installMD = Gate.repoRoot().appendingPathComponent("docs/INSTALL.md")
        let mdText = try String(contentsOf: installMD, encoding: .utf8)
        let mdHits = Self.needles.filter { mdText.contains($0) }
        #expect(mdHits.isEmpty, "docs/INSTALL.md 仍出現：\(mdHits.joined(separator: "、"))")

        let auraCoreDir = Gate.repoRoot().appendingPathComponent("Sources/AuraCore")
        let (scannedCore, hitsCore) = try Self.scan(under: auraCoreDir)
        #expect(scannedCore >= 5, "Sources/AuraCore/ 只讀到 \(scannedCore) 個檔 —— gate 不能空跑")
        #expect(hitsCore.isEmpty, """
            Sources/AuraCore/ 仍出現「捷徑」或「連結」指掛載這個概念：
            \(hitsCore.map { "\($0.0.lastPathComponent)（\($0.1)）" }.sorted().joined(separator: "、"))
            """)
    }

    @Test("正向對照：掃描函式對真違規會紅")
    func scanCatchesRealViolation() throws {
        try Gate.withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("Probe.swift")
            try ("這是一個" + Self.needles[0]).write(to: probe, atomically: true, encoding: .utf8)
            let (scanned, hits) = try Self.scan(under: dir)
            #expect(scanned == 1)
            #expect(!hits.isEmpty, "掃描函式沒抓到 probe 裡的違規字樣 —— 解析壞了會讓所有東西看起來都乾淨")
        }
    }

    @Test("正向對照：allowedFiles 清單裡的檔名即使含違規字樣也不計入 hits")
    func allowedFilesAreExcludedFromHits() throws {
        try Gate.withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("RunningBundle.swift")
            try ("這是一個" + Self.needles[1]).write(to: probe, atomically: true, encoding: .utf8)
            let (_, hits) = try Self.scan(under: dir)
            #expect(hits.isEmpty, "allowedFiles 裡的檔名（RunningBundle.swift）不該被算進 hits")
        }
    }

    @Test("釘死允許清單：只准恰好是 RunningBundle.swift，多一個都要紅")
    func allowedFilesArePinned() throws {
        #expect(Self.allowedFiles == ["RunningBundle.swift"], """
            allowedFiles 被改動了，實際：\(Self.allowedFiles.sorted())。
            這份清單只准手動改這份原始碼並經過 review，不准被悄悄加大來放行新的用語違規。
            """)
    }
}
