import Testing
import Foundation

/// D-5(1)：字串表機制「少翻一個字串＝編譯錯誤」的地基是**窮盡 switch、無 default**——
/// 這是編譯器不會幫你查的事（`default:` 一樣編得過），要靠來源掃描頂住「有人手滑加了
/// default」。掃描對象是**字串表本身**（`Sources/AuraCore/L10n*.swift`），不是全部
/// `Sources/`——別處的 switch（例如 `PanelActionKind` 的窮盡 switch）本來就不歸這條管。
@Suite("D-5(1)：字串表（L10n*.swift）沒有 default 分支")
struct L10nExhaustivenessSourceScanTests {

    /// 找 `Sources/AuraCore/` 底下檔名以 `L10n` 開頭的 `.swift` 檔——這就是字串表本體
    /// （`L10nCatalog.swift` 這個 protocol 定義檔本身沒有 switch，掃到也不會有 hit）。
    static func l10nFiles(under directory: URL) throws -> [URL] {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw Gate.GateFailure("列不出目錄：\(directory.path)")
        }
        return e.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent.hasPrefix("L10n") }
    }

    /// `default` 加冒號的樣式——同 `UserDefaultsSourceScan` 的作法（帶標點鎖定 case 標籤，
    /// 不是任意提及這個字）。這份檔案自己的原始碼因此不能在中文說明裡直接打出這個組合，
    /// 用字串拼接繞開（同 `TerminologyUnificationSourceScanTests` 的解法，避免自我命中）。
    static let needle = "defau" + "lt:"

    static func hasDefaultBranch(_ text: String) -> Bool {
        text.contains(needle) || text.contains("defau" + "lt :")
    }

    @Test("Sources/AuraCore/L10n*.swift 沒有任何檔案含 default 分支")
    func noDefaultBranch() throws {
        let dir = Gate.repoRoot().appendingPathComponent("Sources/AuraCore")
        let files = try Self.l10nFiles(under: dir)
        #expect(files.count >= 3, "只掃到 \(files.count) 個 L10n*.swift —— gate 不能空跑")
        var hits: [String] = []
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)   // 讀不到 → 大聲紅，不是乾淨
            if Self.hasDefaultBranch(text) { hits.append(url.lastPathComponent) }
        }
        #expect(hits.isEmpty, """
            以下字串表檔案出現 default 分支，會讓「少翻一個字串＝編譯錯誤」失效：
            \(hits.sorted())——新增 Language case 時，這些檔案的 switch 不會編不過，
            會靜默漏翻
            """)
    }

    @Test("正向對照：掃描函式對真的 default 分支會紅")
    func scanCatchesRealDefaultBranch() throws {
        let probeText = "switch language {\ncase .english: return \"x\"\n" + Self.needle + " return \"y\"\n}\n"
        #expect(Self.hasDefaultBranch(probeText), "掃描函式沒抓到 probe 裡真的有的 default 分支")
    }

    @Test("負對照：沒有 default 分支的檔案不會被誤判")
    func scanDoesNotFlagCleanFile() throws {
        let clean = """
            enum L10nProbe {
                func text(_ language: Language) -> String {
                    switch language {
                    case .english: return "x"
                    case .traditionalChinese: return "y"
                    }
                }
            }
            """
        #expect(!Self.hasDefaultBranch(clean), "乾淨檔案不該被判成有 default 分支")
    }
}
