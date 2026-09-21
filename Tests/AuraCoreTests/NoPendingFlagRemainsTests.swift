import Testing
import Foundation

/// T12（CX44）：`Sources/` ＋ `Tests/` 都不得殘留「pending stub」標記
/// （字面組成見 `needle`：`AURA_CODEX` 前綴 ＋ `_PENDING` 後綴，接 `_T<nn>`）。
///
/// **為什麼**：plan §0（`docs/superpowers/plans/2026-09-18-codex-support.md`）要求「所有等下一個
/// task 替換的 stub，一律在註解貼」這個標記（接 task 編號）。T05／T10 的驗收已經要求解除，
/// 但那靠人記得——這條 gate 讓「解除了沒有」不必靠人記得，直接掃磁碟。
///
/// **不能比照 CX30 過濾註解行**：CX30（`NoCodexExecInRepoTests`）過濾註解是因為「提到指令名」
/// 不算違規，只有「真的會被執行」才算；這裡恰好相反——標記的使用慣例就是**只**寫在註解裡
/// （`// ` 或 `///` 開頭），標記本身出現即是違規，過濾註解等於永遠抓不到真正的殘留。
/// 因此本檔的 doc comment 全程避免把完整字面連續拼出來（見上方「字面組成」的拆法），
/// 否則這份 gate 檔會抓到自己。
///
/// **兩個 root 都要掃**（T07 的四個 stub 裡有三個在 `Sources/`，只掃 `Tests/` 會漏掉）：
/// mutation 要求「在 `Sources/` 與 `Tests/` 各留一個標記（接 `_T08`）→ 兩處都要紅」，
/// 比照既有 `noStrayLiteralOutsideAllowlist`／`noCodexExecInRepo` 的形狀（同一套 scan-and-hit）。
@Suite("T12：Sources／Tests 不得殘留 pending stub 標記（CX44）")
struct NoPendingFlagRemainsTests {
    // 串接組出來，這份 gate 檔自己的原始碼因此不含完整字面，不會撞到自己。
    private static let needle = "AURA_CODEX" + "_PENDING"

    static func scan(under directory: URL) throws -> (scanned: Int, hits: [URL]) {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw Gate.GateFailure("列不出目錄：\(directory.path)")
        }
        let files = e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        var hits: [URL] = []
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)   // 讀不到 → 大聲紅，不是安靜放行
            if text.contains(needle) { hits.append(url) }
        }
        return (files.count, hits)
    }

    @Test("Sources/ 底下不得殘留 pending stub 標記")
    func sourcesHasNoPendingFlag() throws {
        let dir = Gate.repoRoot().appendingPathComponent("Sources")
        let (scanned, hits) = try Self.scan(under: dir)
        #expect(scanned >= 50, "只掃到 \(scanned) 個 .swift —— gate 不能空跑")
        #expect(hits.isEmpty, """
            以下檔案殘留 pending stub 標記，代表某個 stub 還沒被真實作取代：
            \(hits.map(\.lastPathComponent).sorted())
            """)
    }

    @Test("Tests/ 底下不得殘留 pending stub 標記")
    func testsHasNoPendingFlag() throws {
        let dir = Gate.repoRoot().appendingPathComponent("Tests")
        let (scanned, hits) = try Self.scan(under: dir)
        #expect(scanned >= 50, "只掃到 \(scanned) 個 .swift —— gate 不能空跑")
        #expect(hits.isEmpty, """
            以下檔案殘留 pending stub 標記，代表某個 pending 仍未解除：
            \(hits.map(\.lastPathComponent).sorted())
            """)
    }

    /// 正向對照：暫存目錄放一個真的含標記的 probe，證明掃描沒壞。
    @Test("正向對照：掃描函式對真殘留會紅")
    func scanCatchesRealPendingFlag() throws {
        try Gate.withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("Stub.swift")
            try ("// " + Self.needle + "_T08\nlet x = 1\n").write(to: probe, atomically: true, encoding: .utf8)
            let (scanned, hits) = try Self.scan(under: dir)
            #expect(scanned == 1)
            #expect(!hits.isEmpty, "掃描函式沒抓到 probe 裡的殘留標記 —— 解析壞了會讓所有東西看起來都乾淨")
        }
    }

    /// 正向對照：不含標記的檔案不算違規。
    @Test("正向對照：乾淨檔案不算違規")
    func scanDoesNotFlagCleanFiles() throws {
        try Gate.withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("Clean.swift")
            try "let x = 1".write(to: probe, atomically: true, encoding: .utf8)
            let (_, hits) = try Self.scan(under: dir)
            #expect(hits.isEmpty)
        }
    }
}
