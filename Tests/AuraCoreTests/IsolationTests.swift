import Testing
import Foundation

@Suite("AuraCore 隔離約束")
struct IsolationTests {

    /// 從測試檔位置往上找 repo 根目錄。
    static func repoRoot() -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        while dir.pathComponents.count > 1 {
            dir = dir.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir
            }
        }
        fatalError("找不到 Package.swift")
    }

    static func swiftFiles(under relative: String) -> [URL] {
        let root = repoRoot().appendingPathComponent(relative)
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    // MARK: - Stage 1：把註解與字串字面值中性化

    /// Swift 詞法層的行終止符。中性化時原樣保留，`(?m)^` 的行首錨定與行號才不位移。
    static let lineTerminators: Set<Unicode.Scalar> = ["\n", "\r", "\u{0B}", "\u{0C}", "\u{85}", "\u{2028}", "\u{2029}"]

    /// 把註解與字串字面值的**內容**換成空白（換行原樣保留），其餘字元不動。
    ///
    /// 為什麼要分兩段做，而不是把 pattern 再改一次：單一 regex 沒辦法同時
    /// (a) 描述 Swift 宣告前綴的文法（attribute 參數可為任意內容）與
    /// (b) 判斷某個位置是不是落在字串／註解裡。兩個目標會互相拉扯，這也是
    /// 前三輪的實際失敗方式——放寬括號內容就誤攔 `@available(…, message: "(x) import …")`；
    /// 為了堵那個誤攔而排除引號，就漏放 `@_documentation(metadata: "foo") import AppKit`
    /// （真的會編譯、真的違規）。詞法層先掃掉字面值，(a) 與 (b) 就解耦了。
    ///
    /// 掃描順序即 Swift lexer 的順序：註解與字串都只能從「正常碼」位置進入，
    /// 所以字串裡的 `//`、`/*` 不會被當成註解，註解裡的引號也不會開啟字串。
    /// 未收尾的單行字串止於行尾（Swift 不允許裸換行），因此掃描狀態在每個換行
    /// 都會回到正常碼——插值裡的巢狀字串最壞只會讓同一行的真實碼露出來，
    /// 不會把後面幾行的真 import 藏起來。
    ///
    /// 輸出與輸入的 scalar 數、行終止符位置完全相同（`neutralizedPreservesLayout` 釘住）。
    static func neutralized(_ source: String) -> String {
        let c = Array(source.unicodeScalars)
        var out = String.UnicodeScalarView()
        out.reserveCapacity(c.count)
        var i = 0
        func at(_ j: Int, _ s: Unicode.Scalar) -> Bool { j < c.count && c[j] == s }
        func hide(_ s: Unicode.Scalar) -> Unicode.Scalar { lineTerminators.contains(s) ? s : " " }

        while i < c.count {
            if c[i] == "/", at(i + 1, "/") {                                  // 行註解：吃到行尾
                while i < c.count, !lineTerminators.contains(c[i]) { out.append(" "); i += 1 }
                continue
            }
            if c[i] == "/", at(i + 1, "*") {                                  // 區塊註解：Swift 可巢狀
                var depth = 0
                repeat {
                    if c[i] == "/", at(i + 1, "*") { depth += 1; out.append(" "); out.append(" "); i += 2 }
                    else if c[i] == "*", at(i + 1, "/") { depth -= 1; out.append(" "); out.append(" "); i += 2 }
                    else { out.append(hide(c[i])); i += 1 }
                } while i < c.count && depth > 0                              // 未收尾就吃到 EOF
                continue
            }
            var hashes = 0                                                    // raw string 的 # 前綴
            while at(i + hashes, "#") { hashes += 1 }
            guard at(i + hashes, "\"") else {                                 // 只有後面接引號才是字串
                out.append(c[i]); i += 1                                      // 否則 # 是 #if / #filePath…
                continue
            }
            let q = i + hashes
            let quoteLen = (at(q + 1, "\"") && at(q + 2, "\"")) ? 3 : 1       // """ 為多行字串
            func closes(at j: Int) -> Bool {                                  // 收尾 = 引號 + 同量的 #
                guard j + quoteLen + hashes <= c.count else { return false }
                for k in 0..<quoteLen where c[j + k] != "\"" { return false }
                for k in 0..<hashes where c[j + quoteLen + k] != "#" { return false }
                return true
            }
            func escapes(at j: Int) -> Bool {                                 // raw string 的跳脫是 \ + 同量的 #
                guard c[j] == "\\", j + hashes + 1 < c.count else { return false }
                for k in 0..<hashes where c[j + 1 + k] != "#" { return false }
                return true
            }
            while i < q + quoteLen { out.append(c[i]); i += 1 }               // 開頭 delimiter 原樣保留
            while i < c.count {
                if quoteLen == 1, lineTerminators.contains(c[i]) { break }    // 未收尾的單行字串止於行尾
                if closes(at: i) {
                    for _ in 0..<(quoteLen + hashes) { out.append(c[i]); i += 1 }
                    break
                }
                if escapes(at: i) {                                           // 跳脫序列整段隱掉，
                    for _ in 0..<(hashes + 2) { out.append(hide(c[i])); i += 1 }  // 才不會把 \" 誤判成收尾
                    continue
                }
                out.append(hide(c[i])); i += 1
            }
        }
        return String(out)
    }

    // MARK: - Stage 2：對中性化後的文字比對宣告前綴

    /// 禁止 `AuraCore` 依賴 AppKit / SwiftUI / Cocoa。
    ///
    /// 字面值已由 stage 1 清掉，所以這裡只需描述 Swift 的 import 宣告前綴：
    /// `import` **之前**可有任意數量的 attribute（`@testable`、`@preconcurrency`、
    /// `@_spi(...)`、`@_documentation(...)` …）與 access-level modifier（Swift 6 的
    /// `internal import` / `public import` / `package import` …）；**之後**可有一個
    /// 宣告關鍵字（scoped import，如 `import class AppKit.NSWindow`）。
    static let bannedImportPattern: String = {
        let modifiers = #"(?:(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)\n]*\))?|public|package|internal|fileprivate|private)[ \t]+)*"#
        let kind = #"(?:(?:class|struct|enum|protocol|typealias|func|var|let|actor|inout)[ \t]+)?"#
        return #"(?m)^[ \t]*"# + modifiers + #"import[ \t]+"# + kind + #"(?:AppKit|SwiftUI|Cocoa)\b"#
    }()

    /// 第一個違規 import 的行號與該行原始文字（行號取自原始碼，靠 stage 1 的位置不變性）。
    static func firstBannedImport(in source: String) -> (line: Int, text: String)? {
        let cleaned = neutralized(source)
        guard let hit = cleaned.range(of: bannedImportPattern, options: .regularExpression) else { return nil }
        let index = cleaned[..<hit.lowerBound].reduce(into: 0) { n, ch in if ch == "\n" { n += 1 } }
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let text = index < lines.count ? String(lines[index]) : String(cleaned[hit])
        return (index + 1, text.trimmingCharacters(in: .whitespaces))
    }

    static func isBannedImport(_ source: String) -> Bool { firstBannedImport(in: source) != nil }

    @Test("AuraCore 不得依賴 AppKit / SwiftUI / Cocoa（含 scoped import）")
    func coreHasNoUIImports() throws {
        for file in Self.swiftFiles(under: "Sources/AuraCore") {
            let src = try String(contentsOf: file, encoding: .utf8)
            let hit = Self.firstBannedImport(in: src)
            #expect(hit == nil,
                    "\(file.lastPathComponent):\(hit?.line ?? 0) 出現禁止的 import：\(hit?.text ?? "")")
        }
    }

    @Test("gate 涵蓋 Swift 完整的 import 語法")
    func importPatternCoverage() {
        // 全部以 swiftc -typecheck 確認是「真的會編譯」的形狀。
        let shouldMatch = [
            "import AppKit",
            "  import AppKit",
            "\timport SwiftUI",
            "import Cocoa",
            "@testable import AppKit",
            "import class AppKit.NSWindow",                     // scoped
            "import struct SwiftUI.Color",
            "import AppKit.NSWindow",                           // submodule，無宣告關鍵字
            "@preconcurrency import AppKit",
            "@_exported import AppKit",
            "@_implementationOnly import AppKit",
            "@_spi(Private) import AppKit",                     // attribute 參數為 identifier
            // 前三輪的漏放與誤攔都出在這一族：attribute 參數可以是字串，字串裡
            // 可以有右括號、跳脫引號，甚至整個是 raw string。四者皆經 typecheck。
            #"@_documentation(metadata: "foo") import AppKit"#,
            #"@_documentation(metadata: "a ) b") import AppKit"#,
            #"@_documentation(metadata: "a\"b") import AppKit"#,
            ##"@_documentation(metadata: #"a"#) import AppKit"##,
            "@_documentation(metadata: foo) import AppKit",
            "@_documentation(visibility: private) import AppKit",
            "@_documentation(visibility: internal) import AppKit",
            "internal import AppKit",                           // Swift 6 access-level import
            "public import AppKit",
            "package import AppKit",
            "fileprivate import SwiftUI",
            "private import Cocoa",
            "@preconcurrency internal import AppKit",           // attribute + modifier 疊加
            "internal import struct AppKit.NSView",             // modifier + scoped
            "@_spi(Private) internal import class AppKit.NSView", // 三者疊加
            "import AppKit // 尾隨註解",
            "/* 註解 */ import AppKit",                          // 註解在前，import 仍在
        ]
        let shouldNotMatch = [
            // round 2 的誤攔：attribute 的字串參數裡剛好有右括號與 import 字樣。
            #"@available(*, deprecated, message: "(legacy) import SwiftUI wrapper removed")"#,
            #"@available(*, deprecated, message: "(see docs) import AppKit is banned")"#,
            "/// 此 module 不得依賴 AppKit",
            "// 不要 import AppKit 進來",
            "/// internal import AppKit 是禁止的",
            "    // import AppKit",
            "import Foundation",
            "internal import Foundation",
            #"let s = "import AppKit""#,
            "importAppKit",
            "public func importAppKitThing() {}",
            "#if canImport(AppKit)",
            #"let url = "https://example.com/import%20AppKit""#,  // 字串裡的 // 不是註解
            ##"let s = #"import AppKit"#"##,                       // raw string
            ###"let s = ##"internal import AppKit"##"###,          // 兩個 # 的 raw string
            #"let s = "\(x) import AppKit""#,                      // 插值
            // 以下三個曾被記為「要 parse Swift 才修得動」的已知限制，stage 1 一併解決。
            """
            /* 說明
            internal import AppKit
            */
            """,
            """
            /* 外層 /* 內層
            internal import AppKit
            */ 仍在外層註解裡
            */
            """,
            #"""
            let doc = """
            internal import AppKit
            """
            """#,
            ##"""
            let doc = #"""
            import AppKit
            """#
            """##,
        ]
        // 釘住 corpus 規模：案例只能加不能減（Lessons Learned #3，防止日後「弱化讓它過」）。
        #expect(shouldMatch.count == 29)
        #expect(shouldNotMatch.count == 20)
        for source in shouldMatch {
            #expect(Self.isBannedImport(source), "應攔下：\(source)")
        }
        for source in shouldNotMatch {
            #expect(!Self.isBannedImport(source), "不該攔：\(source)")
        }
    }

    @Test("中性化正確處理每一種註解與字串字面值")
    func neutralizerHandlesEveryLiteralForm() {
        #expect(Self.neutralized("a // x\nb") == "a     \nb", "行註解")
        #expect(Self.neutralized("a /* x /* y */ z */ b") == "a                   b", "巢狀區塊註解")
        #expect(Self.neutralized("let s = \"\"\"\nimport AppKit\n\"\"\"\n")
                == "let s = \"\"\"\n             \n\"\"\"\n", "多行字串")
        #expect(Self.neutralized(#""a\"b" x"#) == #""    " x"#, "單行字串裡的跳脫引號")
        #expect(Self.neutralized(##"#"a\"b"# x"##) == ##"#"    "# x"##, "raw string 裡的 \\\" 不是跳脫")
        #expect(Self.neutralized(###"##"a"# b"## c"###) == ###"##"     "## c"###, "兩個 # 的 raw string")
        #expect(Self.neutralized("a /* x\ny") == "a     \n ", "未收尾的區塊註解吃到 EOF")
        #expect(Self.neutralized("\"abc\nimport AppKit") == "\"   \nimport AppKit",
                "未收尾的單行字串止於行尾——後面幾行的真 import 不能被藏起來")
        #expect(Self.neutralized("// a\n// b\n") == "    \n    \n", "連續行註解")
    }

    @Test("中性化不改變長度與行終止符位置")
    func neutralizedPreservesLayout() throws {
        func terminators(_ text: String) -> [Int] {
            text.unicodeScalars.enumerated()
                .filter { Self.lineTerminators.contains($0.element) }
                .map(\.offset)
        }
        var samples = [
            "", "\n", "a", "// x", "/* x", "\"", "#\"", "\"\"\"", "a\r\nb\r\n",
            "/* a\n/* b\n*/\n*/\n", "let s = \"\"\"\nx\n\"\"\"\n", "#\"\"\"\nx\n\"\"\"#\n",
        ]
        for dir in ["Sources/AuraCore", "Sources/AuraHookFile", "Sources/aura-hook", "Tests/AuraCoreTests"] {
            for file in Self.swiftFiles(under: dir) {
                samples.append(try String(contentsOf: file, encoding: .utf8))
            }
        }
        for source in samples {
            let cleaned = Self.neutralized(source)
            #expect(cleaned.unicodeScalars.count == source.unicodeScalars.count,
                    "長度必須不變，否則行首錨定與行號都會位移：\(source.debugDescription)")
            #expect(terminators(cleaned) == terminators(source),
                    "行終止符位置必須不變：\(source.debugDescription)")
        }
    }

    /// 正確算行數。
    ///
    /// `split(separator: "\n", omittingEmptySubsequences: false).count` 對結尾有換行的
    /// 檔案會多算 1（`"a\nb\n"` → 3），使「≤200」實際擋在 199 —— 恰好 200 行的合法檔案
    /// 會被誤判成 201 行。改成數換行字元。
    static func lineCount(of text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let newlines = text.reduce(into: 0) { acc, ch in if ch == "\n" { acc += 1 } }
        return text.hasSuffix("\n") ? newlines : newlines + 1
    }

    @Test("lineCount 對結尾有／無換行都正確")
    func lineCountIsExact() {
        #expect(Self.lineCount(of: "") == 0)
        #expect(Self.lineCount(of: "a") == 1)
        #expect(Self.lineCount(of: "a\n") == 1)
        #expect(Self.lineCount(of: "a\nb") == 2)
        #expect(Self.lineCount(of: "a\nb\n") == 2, "結尾換行不得多算一行")
        #expect(Self.lineCount(of: String(repeating: "x\n", count: 200)) == 200)
    }

    @Test("每個原始檔不得超過 200 行")
    func fileLengthLimit() throws {
        for dir in ["Sources/AuraCore", "Sources/AuraHookFile", "Sources/aura-hook"] {
            for file in Self.swiftFiles(under: dir) {
                let lines = Self.lineCount(of: try String(contentsOf: file, encoding: .utf8))
                #expect(lines <= 200, "\(file.lastPathComponent) 有 \(lines) 行，超過 200 行上限")
            }
        }
    }
}

@Suite("Fixture 完整性")
struct FixtureIntegrityTests {

    @Test("round1 含 15 個 PreToolUse 與 14 個 PostToolUse")
    func round1Counts() throws {
        let all = try Fixtures.rawEvents(named: "round1") + Fixtures.rawEvents(named: "round1b")
        let counts = Dictionary(grouping: all) { $0["hook_event_name"] as? String ?? "?" }
            .mapValues(\.count)
        #expect(counts["PreToolUse"] == 15)
        #expect(counts["PostToolUse"] == 14)
        #expect(counts["SessionStart"] == 1)
        #expect(counts["Stop"] == 1)
        #expect(counts["SessionEnd"] == 1)
    }

    @Test("round1 的 effort 是物件形狀，不是字串")
    func effortIsObject() throws {
        let pre = try Fixtures.events(named: "round1", kind: "PreToolUse")
        let effort = try #require(pre.first?["effort"])
        #expect(effort is [String: Any], "實測 effort 是 {\"level\":…} 物件（spec §2.1.1）")
    }

    @Test("round1 沒有任何 event 帶 model，round2 的 SessionStart 有")
    func modelFieldOnlyOnSessionStart() throws {
        let r1 = try Fixtures.rawEvents(named: "round1") + Fixtures.rawEvents(named: "round1b")
        #expect(r1.allSatisfy { $0["model"] == nil }, "第一輪：無 model")

        let starts = try Fixtures.events(named: "round2", kind: "SessionStart")
        #expect(!starts.isEmpty)
        #expect(starts.allSatisfy { $0["model"] is String },
                "第二輪實測：SessionStart 帶 model（spec §2.1.1，第二輪為準）")
        // 其他 event 仍然不帶 —— 故 model 必須由 MergeRules 帶過來
        let others = try Fixtures.rawEvents(named: "round2")
            .filter { $0["hook_event_name"] as? String != "SessionStart" }
        #expect(others.allSatisfy { $0["model"] == nil })
    }

    @Test("round2 有捕獲 Notification，notification_type 與 message 皆經量測確認")
    func round2HasNotification() throws {
        let notifs = try Fixtures.events(named: "round2", kind: "Notification")
        #expect(!notifs.isEmpty, "Task 01 必須捕獲至少 1 筆 Notification")
        #expect(notifs.allSatisfy { $0["notification_type"] is String },
                "欄位名必須經實測確認，不能只靠文件")
        #expect(notifs.allSatisfy { $0["message"] is String },
                "實測發現的額外欄位（spec §2.1.2）")
    }

    @Test("round2 的 SubagentStop 有 agent_type 為空字串的內部 subagent")
    func round2HasInternalSubagent() throws {
        let stops = try Fixtures.events(named: "round2", kind: "SubagentStop")
        #expect(!stops.isEmpty)
        #expect(stops.contains { ($0["agent_type"] as? String) == "" },
                "內部 subagent 的 agent_type 是空字串而非 null —— §2.5.1 critical bug 的來源")
        #expect(stops.allSatisfy { ($0["agent_id"] as? String)?.isEmpty == false })
    }

    @Test("round2 裡 SubagentStop 出現在主 agent Stop 之後（§2.5.1 的時序證據）")
    func round2SubagentStopAfterStop() throws {
        // 探針的外層有 _t 時戳，rawEvents 已剝掉；這裡直接讀原始行。
        let url = try #require(Bundle.module.url(forResource: "Fixtures/round2", withExtension: "ndjson"))
        struct Row { let t: Double; let sid: String; let event: String; let isSub: Bool }
        let rows: [Row] = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n").compactMap { line in
                guard let d = line.data(using: .utf8),
                      let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let t = o["_t"] as? Double,
                      let p = o["_payload"] as? [String: Any],
                      let sid = p["session_id"] as? String,
                      let ev = p["hook_event_name"] as? String else { return nil }
                return Row(t: t, sid: sid, event: ev,
                           isSub: (p["agent_id"] as? String)?.isEmpty == false)
            }
        var found = false
        for sid in Set(rows.map(\.sid)) {
            let mine = rows.filter { $0.sid == sid }
            guard let stop = mine.first(where: { $0.event == "Stop" && !$0.isSub })?.t,
                  let subStop = mine.first(where: { $0.event == "SubagentStop" })?.t
            else { continue }
            if subStop > stop { found = true }
        }
        #expect(found, "至少一個 session 的 SubagentStop 晚於 Stop —— 這是 §2.5.1 的實測依據")
    }
}
