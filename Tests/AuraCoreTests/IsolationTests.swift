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

    /// 禁止 `AuraCore` 依賴 AppKit / SwiftUI / Cocoa。
    ///
    /// 必須涵蓋 Swift 完整的 import 語法，而不只是 `import AppKit` 這一種形狀：
    /// `import` **之前**可以有任意數量的 attribute（`@testable`、`@preconcurrency`、
    /// `@_exported`、`@_spi(...)` …）與 access-level modifier（Swift 6 的
    /// `internal import` / `public import` / `package import` …）；**之後**可以有一個
    /// 宣告關鍵字（scoped import，如 `import class AppKit.NSWindow`）。
    /// 錨定在行首，所以散文註解與字串字面值不會誤觸。
    static let bannedImportPattern: String = {
        let modifiers = #"(?:(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)\n]*\))?|public|package|internal|fileprivate|private)[ \t]+)*"#
        let kind = #"(?:(?:class|struct|enum|protocol|typealias|func|var|let|actor|inout)[ \t]+)?"#
        return #"(?m)^[ \t]*"# + modifiers + #"import[ \t]+"# + kind + #"(?:AppKit|SwiftUI|Cocoa)\b"#
    }()

    @Test("AuraCore 不得依賴 AppKit / SwiftUI / Cocoa（含 scoped import）")
    func coreHasNoUIImports() throws {
        for file in Self.swiftFiles(under: "Sources/AuraCore") {
            let src = try String(contentsOf: file, encoding: .utf8)
            let hit = src.range(of: Self.bannedImportPattern, options: .regularExpression)
            #expect(hit == nil,
                    "\(file.lastPathComponent) 出現禁止的 import：\(hit.map { String(src[$0]) } ?? "")")
        }
    }

    @Test("regex gate 涵蓋 Swift 完整的 import 語法")
    func importPatternCoverage() {
        let shouldMatch = [
            "import AppKit",
            "  import AppKit",
            "\timport SwiftUI",
            "import Cocoa",
            "@testable import AppKit",
            "import class AppKit.NSWindow",            // scoped
            "import struct SwiftUI.Color",
            "import AppKit.NSWindow",                  // submodule，無宣告關鍵字
            "@preconcurrency import AppKit",           // Swift 6 常見
            "@_exported import AppKit",
            "@_implementationOnly import AppKit",
            "@_spi(Private) import AppKit",
            "internal import AppKit",                  // Swift 6 access-level import
            "public import AppKit",
            "package import AppKit",
            "fileprivate import SwiftUI",
            "private import Cocoa",
            "@preconcurrency internal import AppKit",  // 兩者疊加
            "internal import struct AppKit.NSView",    // modifier + scoped
        ]
        let shouldNotMatch = [
            "/// 此 module 不得依賴 AppKit",
            "// 不要 import AppKit 進來",
            "/// internal import AppKit 是禁止的",
            "    // import AppKit",
            "import Foundation",
            "internal import Foundation",
            "let s = \"import AppKit\"",
            "importAppKit",
            "public func importAppKitThing() {}",
            "#if canImport(AppKit)",
        ]
        for line in shouldMatch {
            #expect(line.range(of: Self.bannedImportPattern, options: .regularExpression) != nil,
                    "應攔下：\(line)")
        }
        for line in shouldNotMatch {
            #expect(line.range(of: Self.bannedImportPattern, options: .regularExpression) == nil,
                    "不該攔：\(line)")
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
