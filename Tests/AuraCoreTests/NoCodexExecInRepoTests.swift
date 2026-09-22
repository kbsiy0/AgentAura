import Testing
import Foundation

/// T11（CX30，F12）：`Tests/`／`scripts/`／`.github/` 底下不得出現 `codex exec` 這個指令字面。
///
/// **為什麼**：探針量到（`docs/2026-09-18-codex-hook-probe.md` F12）`codex exec` 會在
/// **使用者自己的** `~/.codex/config.toml` 寫入 `[projects."<cwd>"] trust_level = "trusted"`——
/// 這是 Codex 對工作目錄的標準行為，跟 hook 無關，但任何驗收腳本或測試若真的執行它，
/// 都會動到使用者機器上這份設定檔。同 plan §0（`docs/superpowers/plans/2026-09-18-codex-support.md`）
/// 明令禁止的「在任何地方跑 `codex exec`」，與 CLAUDE.md「Agent 在終端機裡的界線」
/// 同一種道理——查文件不等於執行一次看看。
///
/// **roots 是「誰真的會執行指令」，不是「誰提到 Codex」**（T11c，spec-reviewer 問題 2／
/// 主 session 追加驗證）：`Tests/`／`scripts/` 是本 repo 原本就有的兩個可執行面；
/// `.github/`（`workflows/ci.yml`）是第三個——GitHub Actions runner 會逐行跑 `run:` 步驟，
/// 跟 shell 腳本同一種風險等級，**先前審查誤判這個 repo 沒有 CI 設定檔，實際上有**。
/// `docs/` **刻意不納入**：那個目錄不執行任何東西，而 `docs/2026-09-18-codex-hook-probe.md`
/// 的 F12 段落**必須**逐字寫出這個指令名才說得清楚證據——把 `docs/` 納入等於逼證據文件
/// 改用迂迴措辭，或另外養一份 allowlist，兩者都比現狀差。**將來新增任何可執行面
/// （例如第二個 CI 設定檔／Makefile）時，roots 要跟著加**——沒有任何測試會在那個時間點
/// 自動提醒你，這是本 repo「涵蓋每一個 X 要從磁碟／型別推導」原則在這裡的殘餘缺口，
/// 誠實記在這裡比假裝涵蓋更好。
@Suite("Tests／scripts／.github 不得出現 F12 那個會動使用者 config.toml 的指令字面（CX30）")
struct NoCodexExecInRepoTests {
    // 串接組出來，這份 gate 檔自己的原始碼因此不含完整字面，不會撞到自己
    // （同 `TerminologyUnificationSourceScanTests`／`SpawnGateCoverageSourceScanTests` 的解法）。
    private static let needle = "codex" + " exec"

    /// **註解不算觸發**（同 `SpawnGateCoverageSourceScanTests` 的既有理由）：
    /// `CodexEventsTests.swift` 有一句 doc comment 記錄「探針 `codex exec` 實抓」，
    /// 那是描述探針工具包（repo 外的一支拋棄式腳本）當年怎麼捕捉 payload 的歷史事實，
    /// 不是這個測試套件裡真的會執行的東西——對「提到」開火只會產生噪音、訓練人忽略它。
    /// `.swift`／`.sh` 註解前綴 `//`（含 `///`）與 `#` 都濾掉；`.yml`／`.yaml`（GitHub
    /// Actions 設定檔）的註解前綴同樣是 `#`，沿用同一套過濾，不必另開一套。
    static func scan(under directory: URL) throws -> (scanned: Int, hits: [URL]) {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw Gate.GateFailure("列不出目錄：\(directory.path)")
        }
        let scannedExtensions: Set<String> = ["swift", "sh", "yml", "yaml"]
        let files = e.compactMap { $0 as? URL }.filter { scannedExtensions.contains($0.pathExtension) }
        var hits: [URL] = []
        for url in files {
            let raw = try String(contentsOf: url, encoding: .utf8)   // 讀不到 → 大聲紅，不是安靜放行
            let code = raw.split(separator: "\n", omittingEmptySubsequences: false)
                .filter {
                    let t = $0.trimmingCharacters(in: .whitespaces)
                    return !t.hasPrefix("//") && !t.hasPrefix("#")
                }
                .joined(separator: "\n")
            if code.contains(needle) { hits.append(url) }
        }
        return (files.count, hits)
    }

    @Test("Tests/、scripts/、.github/ 底下（排除註解）不得出現那個指令字面")
    func noCodexExecInRepo() throws {
        let roots = [
            Gate.repoRoot().appendingPathComponent("Tests"),
            Gate.repoRoot().appendingPathComponent("scripts"),
            Gate.repoRoot().appendingPathComponent(".github"),
        ]
        var totalScanned = 0
        var allHits: [URL] = []
        for root in roots {
            let (scanned, hits) = try Self.scan(under: root)
            // 逐 root 防空轉：`Tests/` 的幾百個 .swift 會把 `.github/` 的零檔完全蓋掉——
            // 副檔名清單少了 `yml`、或 workflow 被搬走改名，全體計數照樣過關，gate 就安靜地
            // 退回只守兩個目錄（T11c review：口徑比宣稱的窄，結果與「乾淨」長得一模一樣）。
            #expect(scanned > 0, "\(root.lastPathComponent)/ 底下掃到 0 個檔 —— 這個 root 在空跑")
            totalScanned += scanned
            allHits += hits
        }
        #expect(totalScanned >= 50, "只讀到 \(totalScanned) 個檔 —— gate 不能空跑")
        #expect(allHits.isEmpty, """
            以下檔案出現「\(Self.needle)」這個可執行的指令字面（不算註解）——F12：這個指令
            會真的在使用者的 ~/.codex/config.toml 寫入 trust_level，測試與驗收腳本
            絕不能執行它：\(allHits.map(\.lastPathComponent).sorted())
            """)
    }

    /// 正向對照：暫存目錄放一個真的含觸發字面（非註解）的 probe，證明掃描抓得到。
    @Test("正向對照：掃描函式對真違規（非註解）會紅")
    func scanCatchesRealViolation() throws {
        try Gate.withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("Probe.sh")
            try ("run() { " + Self.needle + " ; }").write(to: probe, atomically: true, encoding: .utf8)
            let (scanned, hits) = try Self.scan(under: dir)
            #expect(scanned == 1)
            #expect(!hits.isEmpty, "掃描函式沒抓到 probe 裡的違規字樣 —— 解析壞了會讓所有東西看起來都乾淨")
        }
    }

    /// T11c（主 session 指示）：`.github/` 加進 roots 之後，`.yml` 也要納入掃描的副檔名——
    /// `.github/workflows/ci.yml` 是**真的會執行指令**的可執行面（GitHub Actions runner
    /// 逐行跑 `run:` 步驟），跟 `Tests/`／`scripts/` 同一種風險等級；YAML 註解前綴同樣是
    /// `#`，既有的註解過濾邏輯直接沿用，不必另開一套。
    @Test("正向對照：掃描函式對 .yml 檔裡的真違規（非註解）也會紅")
    func scanCatchesRealViolationInYAML() throws {
        try Gate.withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("ci.yml")
            try ("      - run: " + Self.needle).write(to: probe, atomically: true, encoding: .utf8)
            let (scanned, hits) = try Self.scan(under: dir)
            #expect(scanned == 1, "掃描函式沒把 .yml 檔算進 scanned —— .github/ 的可執行面會被靜默漏掃")
            #expect(!hits.isEmpty, "掃描函式沒抓到 .yml 檔 probe 裡的違規字樣")
        }
    }

    /// 正向對照的另一半：只出現在註解裡的同一個字面不算違規——沒有這條，
    /// 「真的有違規」跟「掃描邏輯把註解也當違規」兩種情況會看起來一樣紅。
    @Test("正向對照：只出現在註解裡的那個指令字面不算違規")
    func scanDoesNotFlagCommentOnlyMentions() throws {
        try Gate.withTemporaryDirectory { dir in
            let probeSwift = dir.appendingPathComponent("Probe.swift")
            try ("/// 探針 `" + Self.needle + "` 實抓").write(to: probeSwift, atomically: true, encoding: .utf8)
            let probeSh = dir.appendingPathComponent("Probe.sh")
            try ("# 歷史上探針用過 " + Self.needle).write(to: probeSh, atomically: true, encoding: .utf8)
            let probeYml = dir.appendingPathComponent("ci.yml")
            try ("      # 這一步歷史上曾經跑過 " + Self.needle).write(to: probeYml, atomically: true, encoding: .utf8)
            let (_, hits) = try Self.scan(under: dir)
            #expect(hits.isEmpty, "只出現在註解裡的「\(Self.needle)」不該被判違規，實際：\(hits.map(\.lastPathComponent))")
        }
    }

    /// 正向對照：不含違規字樣的檔案不算違規。
    @Test("正向對照：乾淨檔案不算違規")
    func scanDoesNotFlagCleanFiles() throws {
        try Gate.withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("Probe.swift")
            try "let x = 1".write(to: probe, atomically: true, encoding: .utf8)
            let (_, hits) = try Self.scan(under: dir)
            #expect(hits.isEmpty)
        }
    }
}
