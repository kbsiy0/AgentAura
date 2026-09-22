import Testing
import Foundation

/// **CX58 `everyNamedGateResolvesToAtLeastOneTest`**（T12b 之後的機器化守衛）：
/// 「文件指名的 gate 函式不存在」這個模式已出現第五、六次（r1 M4、鏈 A phase-2 review M1、
/// 鏈 A phase-2 review N1、CX56 review 第四次修正、T12b 這一輪 14 處新命中）——不是偶發，
/// 是 implementer 常把一顆大 gate 拆成多支小函式卻沒回頭同步 DoD 帳本「指名測試」欄。
///
/// **source-derived**：直接解析 `docs/superpowers/plans/2026-09-18-codex-support-dod.md`
/// 的「Gate mutation 帳」markdown 表（表頭含「指名測試」欄的那一張——DoD 裡還有別的表格
/// 也含反引號識別字，鎖定這一張避免把「不歸這張表管的名字」跟「真的漏同步」混為一談），
/// 抽每一列「指名測試」欄裡**反引號包住、且本身是合法 Swift 識別字**的字——過濾掉含空白／
/// 中文／`(`／`.`／`/` 的（那些是概念性描述或程式碼片段，不是字面函式名，同 CX21／CX28
/// 的既有寫法）。對每個留下來的名字，掃 `Tests/` 全部 `.swift` 檔找 `func <名>(`
/// **或** `func <名>_[0-9]+(`（`_n` 後綴聚合慣例，`PanelStatusLabelTests`／
/// `CodexDisconnectConfirmationTests` 等既有先例）。
///
/// **不准 allowlist**：帳本裡的「概念性標籤」（CX21／CX28 那種）本身就已經被上面的
/// 識別字過濾規則排除在「候選名字」之外，不需要、也不准另開一份「已知例外」清單去豁免
/// 一個通過了識別字規則、卻剛好找不到函式的名字——那正是這條 gate 要抓的事。
@Suite("CX58：DoD 帳本「指名測試」欄的每個函式名都能在 Tests/ 找到")
struct NamedGateResolutionTests {

    struct NamedGate: Equatable {
        let gateLabel: String
        let name: String
    }

    // MARK: - 表格解析

    /// markdown 表格的分隔列（`|---|---|...|`，可能含 `:` 對齊符）——去掉 `|`／`-`／`:`／
    /// 空白後應該是空字串。
    static func isSeparatorRow(_ row: String) -> Bool {
        let stripped = row.filter { $0 != "|" && $0 != "-" && $0 != ":" && !$0.isWhitespace }
        return stripped.isEmpty
    }

    /// 只挑「Gate mutation 帳」那張表：從表頭（`|` 開頭、**切成欄位後某一欄恰好等於**
    /// 「指名測試」）開始，到第一個不是 `|` 開頭的行為止（分隔列也算表格的一部分，之後
    /// 濾掉）。**不能只用「這一行含有指名測試四個字」當判準**——DoD 檢查項表（表格更早）
    /// 有一列的**內文**提到「指名測試」這個詞（第 40 行，逐字「`mutation / 指名測試 / 秒數`」），
    /// 那一行本身也是 `|` 開頭的表格列，用子字串比對會誤判成表頭，把完全不同的一張表當成
    /// 目標（本 gate 開發時實測踩到：解析出的候選名字變成 DoD 檢查項表裡的 `diff`／
    /// `ContinuousClock`／`applicationDidFinishLaunching` 這幾個字，跟 CX 系列毫無關係）。
    static func gateTableDataRows(_ fullText: String) -> [String] {
        let lines = fullText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let headerIndex = lines.firstIndex(where: { line in
            guard line.hasPrefix("|") else { return false }
            return cells(of: line).contains("指名測試")
        }) else {
            return []
        }
        var rows: [String] = []
        for line in lines[(headerIndex + 1)...] {
            guard line.hasPrefix("|") else { break }
            if isSeparatorRow(line) { continue }
            rows.append(line)
        }
        return rows
    }

    /// markdown 表格用 `|` 分隔欄位；`\|` 是跳脫過的字面管線字元（本表目前沒有，但別處
    /// 帳本文字裡有，例如 `O_CREAT\|O_EXCL`），先保護起來再切，避免把它當成欄位分隔。
    static func cells(of row: String) -> [String] {
        let placeholder = "\u{0}"
        let protectedRow = row.replacingOccurrences(of: "\\|", with: placeholder)
        return protectedRow.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: placeholder, with: "|").trimmingCharacters(in: .whitespaces) }
    }

    /// 欄序：`| Gate | 位置 | Mutation | 指名測試 | 秒數 | 來源 task |`——
    /// `cells[0]` 是開頭 `|` 前的空字串，`cells[1]` 是 Gate 欄，`cells[4]` 是「指名測試」欄。
    static let gateColumnIndex = 1
    static let namedTestColumnIndex = 4

    static func backtickSpans(_ text: String) -> [String] {
        let parts = text.components(separatedBy: "`")
        guard parts.count > 1 else { return [] }
        var spans: [String] = []
        var i = 1
        while i < parts.count {
            spans.append(parts[i])
            i += 2
        }
        return spans
    }

    static let identifierStartCharacters = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_")
    static let identifierCharacters = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")

    /// `[A-Za-z_][A-Za-z0-9_]*`——過濾掉含空白／中文／`(`／`.`／`/` 的反引號內容
    /// （那些字元都不在上面兩個 `CharacterSet` 裡，中文字元也不是 ASCII，天然被排除）。
    static func isPlainIdentifier(_ s: String) -> Bool {
        guard let first = s.unicodeScalars.first, identifierStartCharacters.contains(first) else { return false }
        return s.unicodeScalars.allSatisfy { identifierCharacters.contains($0) }
    }

    /// **第一輪實跑踩到的三種假陽性**（過濾掉含空白／中文／`(` 這條規則不夠用，實測撞到）：
    /// ①`JSONSerialization`／`CodexInstaller`——**型別名**，本 repo 一律 UpperCamelCase，
    /// 函式一律 lowerCamelCase（`swift-testing` 慣例＋本檔案掃過的每一個真 gate 名都印證），
    /// 開頭大寫的反引號內容不可能是函式名。②`nil`——Swift 保留字，語法上**不能**當識別字，
    /// 出現在反引號裡只會是「這句話在講 nil 這個值」。③`contents`／`unsupportedCharacters`／
    /// `codexSnippet`／`connectClaude`——**逐一 grep 過 `Sources/`／`Tests/` 確認**：分別是
    /// `CodexHookStore.contents`（屬性）、`CodexHookPathCheck.unsupportedCharacters`
    /// （static let）、`PanelModel.codexSnippet`（屬性）、`CodexCoexistenceSequenceTests`
    /// 裡一個列舉 case——四個都是解釋文字裡順手提到的**資料符號**，不是「這一列在指名的
    /// 測試」。同一個字面若同時是 `case`／`let`／`var` 宣告，就不可能又是這一列真正要指名
    /// 的函式，用這個交叉比對排除，比猜字數／字長更站得住腳（也更抓得住新出現的同類噪音）。
    static let swiftReservedIdentifiers: Set<String> = ["nil", "true", "false", "self", "Self", "some", "any"]

    static func startsWithUppercaseASCIILetter(_ s: String) -> Bool {
        guard let first = s.unicodeScalars.first else { return false }
        return ("A"..."Z").contains(Character(first))
    }

    /// 同一個字面若在 `Sources/`／`Tests/` 任何地方被宣告成 `case X`／`let X`／`var X`
    /// （非函式的資料符號），就不可能同時是某一列「指名測試」真正要指的函式——
    /// 用來排除③那三類假陽性。要求宣告後緊接的字元不是識別字字元，避免
    /// `let contents` 誤配到 `let contentsForSomethingElse` 這種前綴巧合。
    static func isDeclaredAsNonFunctionSymbol(_ name: String, in text: String) -> Bool {
        for keyword in ["case ", "let ", "var "] {
            let prefix = keyword + name
            for r in allOccurrenceRanges(of: prefix, in: text) {
                let idx = r.upperBound
                if idx == text.endIndex { return true }
                let next = text[idx]
                if !(next.isLetter || next.isNumber || next == "_") { return true }
            }
        }
        return false
    }

    /// 從 DoD 帳本文字解析出全部 `(gateLabel, name)` 候選——**這是本 gate 唯一的資料來源**。
    /// 只做「這個反引號內容長得像不像識別字」的純文字判斷，**不做**跨檔案交叉比對
    /// （那一步在 `everyNamedGateResolvesToAtLeastOneTest` 裡進行，因為需要讀
    /// `Sources/`／`Tests/`，這個函式保持純函式方便獨立單元測試）。
    static func namedGates(from dodText: String) -> [NamedGate] {
        var result: [NamedGate] = []
        for row in gateTableDataRows(dodText) {
            let parts = cells(of: row)
            guard parts.count > Self.namedTestColumnIndex else { continue }
            let gateLabel = parts[Self.gateColumnIndex]
                .replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !gateLabel.isEmpty else { continue }
            let namedTestCell = parts[Self.namedTestColumnIndex]
            for span in backtickSpans(namedTestCell)
            where isPlainIdentifier(span)
                && !startsWithUppercaseASCIILetter(span)
                && !swiftReservedIdentifiers.contains(span) {
                result.append(NamedGate(gateLabel: gateLabel, name: span))
            }
        }
        return result
    }

    // MARK: - 對照 Tests/／Sources/ 底下真的存在什麼符號

    static func swiftFilesText(under relative: String) throws -> String {
        let dir = Gate.repoRoot().appendingPathComponent(relative)
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else {
            throw Gate.GateFailure("列不出目錄：\(dir.path)")
        }
        let files = e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        guard files.count >= 20 else {
            throw Gate.GateFailure("\(relative)/ 底下只掃到 \(files.count) 個 .swift 檔 —— gate 不能空跑")
        }
        var combined = ""
        for url in files {
            combined += try String(contentsOf: url, encoding: .utf8)
            combined += "\n"
        }
        return combined
    }

    static func allOccurrenceRanges(of needle: String, in haystack: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex,
              let r = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            ranges.append(r)
            searchStart = r.upperBound
        }
        return ranges
    }

    /// `func <name>(` 逐字比對，或 `func <name>_<數字>(`（`_n` 後綴聚合慣例）。
    static func testFunctionExists(_ name: String, in text: String) -> Bool {
        if text.contains("func \(name)(") { return true }
        let prefix = "func \(name)_"
        for r in allOccurrenceRanges(of: prefix, in: text) {
            var idx = r.upperBound
            var sawDigit = false
            while idx < text.endIndex, text[idx].isNumber {
                sawDigit = true
                idx = text.index(after: idx)
            }
            if sawDigit, idx < text.endIndex, text[idx] == "(" { return true }
        }
        return false
    }

    static func pathToDoD() -> URL {
        Gate.repoRoot().appendingPathComponent("docs/superpowers/plans/2026-09-18-codex-support-dod.md")
    }

    @Test("DoD 帳本每個指名的 gate 函式都能在 Tests/ 找到至少一個對應函式")
    func everyNamedGateResolvesToAtLeastOneTest() throws {
        let dodText = try String(contentsOf: Self.pathToDoD(), encoding: .utf8)
        let gates = Self.namedGates(from: dodText)
        #expect(gates.count >= 40, "只解析出 \(gates.count) 個候選名字 —— 解析邏輯可能壞了，gate 不能空轉")

        let testsText = try Self.swiftFilesText(under: "Tests")
        let sourcesText = try Self.swiftFilesText(under: "Sources")
        let combinedForDeclarationCheck = testsText + sourcesText

        // 先用「同一字面在別處被宣告成 case／let／var」濾掉資料符號（見上方 doc comment
        // 的假陽性③），剩下的才是真的要去 Tests/ 找 `func` 的候選。
        let candidates = gates.filter { !Self.isDeclaredAsNonFunctionSymbol($0.name, in: combinedForDeclarationCheck) }
        let missing = candidates.filter { !Self.testFunctionExists($0.name, in: testsText) }
        #expect(missing.isEmpty, """
            以下 \(missing.count) 個 DoD 帳本指名的函式在 Tests/ 底下找不到 `func <名>(` 或 \
            `func <名>_<數字>(`：
            \(missing.map { "\($0.gateLabel)：`\($0.name)`" }.joined(separator: "\n"))
            """)
    }

    // MARK: - 正向與負向對照（解析邏輯本身要先驗證過）

    @Test("正向對照：解析函式抓得到合成資料裡的候選名字，過濾規則正確排除概念性描述")
    func parserExtractsPlainIdentifiersAndFiltersConceptualLabels() {
        let synthetic = """
            | Gate | 位置 | Mutation | 指名測試 | 秒數 | 來源 task |
            |---|---|---|---|---|---|
            | CX-fake | `FakeTests` | 拿掉一行 | `realGateFunction`（＋ `anotherRealOne` 也會紅；概念性描述 `foo.bar()` 與 `has spaces` 與中文標籤都不算） | | T00 |
            """
        let gates = Self.namedGates(from: synthetic)
        #expect(gates.map(\.name) == ["realGateFunction", "anotherRealOne"], """
            解析出的名字應該恰好是 realGateFunction／anotherRealOne，實際 \(gates.map(\.name))
            """)
    }

    @Test("正向對照：合成資料裡真的缺失的函式名會被抓到")
    func parserCatchesRealMissingFunction() {
        let text = "struct Foo {\n    func realFunc() {}\n}\n"
        #expect(Self.testFunctionExists("realFunc", in: text))
        #expect(!Self.testFunctionExists("missingFunc", in: text))
    }

    @Test("正向對照：`_n` 後綴聚合慣例能被找到")
    func parserResolvesNumberedSuffixVariants() {
        let text = "struct Foo {\n    func gateName_1() {}\n    func gateName_2(x: Int) {}\n}\n"
        #expect(Self.testFunctionExists("gateName", in: text))
    }

    @Test("負向對照：分隔列不會被誤判成資料列")
    func separatorRowIsNotADataRow() {
        #expect(Self.isSeparatorRow("|---|---|---|---|---|---|"))
        #expect(Self.isSeparatorRow("|:---|---:|:---:|"))
        #expect(!Self.isSeparatorRow("| CX1 | `Foo` | bar | `baz` | | T01 |"))
    }

    /// 正向對照：實跑第一版撞到的三種假陽性（型別名／保留字／資料符號）都被濾掉。
    @Test("正向對照：型別名、Swift 保留字、以及在別處宣告成 case／let／var 的資料符號都不算候選")
    func parserExcludesTypeNamesKeywordsAndDataSymbols() {
        let synthetic = """
            | Gate | 位置 | Mutation | 指名測試 | 秒數 | 來源 task |
            |---|---|---|---|---|---|
            | CX-fake | `FakeTests` | m | `realGateFunction`：`JSONSerialization` 的輸出／`nil`／`contents` 不做正規化 | | T00 |
            """
        let gates = Self.namedGates(from: synthetic)
        #expect(gates.map(\.name) == ["realGateFunction", "contents"], """
            namedGates 應該已經濾掉 JSONSerialization（型別名）與 nil（保留字），\
            但 contents 這種資料符號要留到跨檔案比對那一步才濾，實際 \(gates.map(\.name))
            """)
        let sourcesText = "struct S {\n    var contents: Data? { nil }\n}\n"
        #expect(Self.isDeclaredAsNonFunctionSymbol("contents", in: sourcesText))
        #expect(!Self.isDeclaredAsNonFunctionSymbol("realGateFunction", in: sourcesText))
    }

    /// 負向對照：`let contents` 不該誤配到 `let contentsForSomethingElse`（前綴巧合）。
    @Test("負向對照：資料符號比對要求完整詞界，不誤配前綴巧合")
    func nonFunctionSymbolCheckRequiresWordBoundary() {
        let text = "struct S {\n    let contentsForSomethingElse = 1\n}\n"
        #expect(!Self.isDeclaredAsNonFunctionSymbol("contents", in: text), """
            「contents」不該被「contentsForSomethingElse」這種前綴巧合誤判成已宣告
            """)
    }
}
