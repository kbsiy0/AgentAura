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

    // MARK: - 隔離 gate：問編譯器，不掃原始碼

    /// 為什麼改成問編譯器（前四輪都掃原始碼文字，每輪都被新的語法形狀打破：scoped
    /// import → access-level import → attribute 字串參數 → regex literal `/…/`、
    /// 插值、「多行字串的開頭 delimiter 後面必須換行」…）：
    ///
    /// 1. 掃文字等於重寫一份 Swift lexer，任何近似都留下繞過空間；
    /// 2. 更關鍵——掃文字答的是「這份**文字**裡有沒有 import AppKit 的字樣」，而
    ///    Global Constraint 問的是「AuraCore **建起來**會不會依賴 AppKit」，且含
    ///    transitive：只寫 `import Mid`、而 Mid 內部 `@_exported import AppKit` 的
    ///    檔案全文「AppKit」出現 0 次，依賴卻是真的（實測 trace 確實回報 AppKit）。
    ///
    /// 編譯器用的就是編譯這個 module 的那套 lexer，答的也正是第 2 個問題 —— 沒有
    /// 語法能騙過它，corpus 也不必隨 Swift 語法演進而增長。
    static let bannedModules: Set<String> = ["AppKit", "SwiftUI", "Cocoa"]

    /// gate 用的 target triple：arch 跟著主機（Intel Mac 也要能跑），最低版本對齊
    /// Package.swift 的 `.macOS(.v13)`，一致性由 `manifestPinsGateAssumptions` 釘住。
    static var gateTarget: String {
        #if arch(arm64)
        "arm64-apple-macos13"
        #elseif arch(x86_64)
        "x86_64-apple-macos13"
        #else
        #error("未支援的架構：請補上這個架構的 gate target triple")
        #endif
    }

    struct GateFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// 全新的暫存目錄。每次都要新的：`-emit-loaded-module-trace-path` 是**附加**寫入
    /// （實測路徑已存在會再接一個 JSON 物件），沿用固定路徑會讀到上一輪的殘留。
    static func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aura-isolation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    /// 問編譯器：把這些檔案編起來會載入哪些 module？任何前提壞掉（沒有輸入檔、swiftc
    /// 失敗、trace 沒寫出來、解析不出 module）一律 throw —— 不准因此變成「乾淨」。
    static func loadedModules(compiling files: [URL], searchPaths: [String] = [],
                              tracePathOverride: String? = nil) throws -> Set<String> {
        guard !files.isEmpty else {
            throw GateFailure("沒有可編譯的原始檔 —— gate 不能空跑")
        }
        return try withTemporaryDirectory { dir in
            let trace = tracePathOverride ?? dir.appendingPathComponent("trace.json").path
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = ["swiftc", "-typecheck", "-target", gateTarget,
                              "-emit-loaded-module-trace", "-emit-loaded-module-trace-path", trace]
                + searchPaths.flatMap { ["-I", $0] } + files.map(\.path)
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            try task.run()
            let log = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            task.waitUntilExit()                       // 先讀完再等，pipe 才不會塞滿卡死

            guard task.terminationStatus == 0 else {
                throw GateFailure("""
                    swiftc 編譯失敗（exit \(task.terminationStatus)），gate 無法作答。
                    這必須是紅燈：前提壞掉時放行，等於把 gate 關掉。
                    指令：swiftc \(task.arguments!.dropFirst().joined(separator: " "))
                    編譯器輸出：
                    \(log)
                    """)
            }
            guard FileManager.default.fileExists(atPath: trace) else {
                throw GateFailure("swiftc 沒有產出 module trace（\(trace)）。編譯器輸出：\n\(log)")
            }
            let text = try String(contentsOfFile: trace, encoding: .utf8)
            var modules: Set<String> = []
            for line in text.split(separator: "\n") where !line.isEmpty {
                guard let data = String(line).data(using: .utf8),
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let infos = object["swiftmodulesDetailedInfo"] as? [[String: Any]]
                else { throw GateFailure("module trace 解析失敗：\(line)") }
                modules.formUnion(infos.compactMap { $0["name"] as? String })
            }
            guard !modules.isEmpty else {
                throw GateFailure("module trace 解析出 0 個 module —— 空 trace 不能讀成「乾淨」（\(trace)）")
            }
            return modules
        }
    }

    @Test("AuraCore 編譯時不得載入 AppKit / SwiftUI / Cocoa")
    func coreLoadsNoUIModules() throws {
        let files = Self.swiftFiles(under: "Sources/AuraCore")   // 掃磁碟，不用手寫清單
        #expect(!files.isEmpty, "掃不到 AuraCore 的原始檔 —— gate 不能空跑")
        let loaded = try Self.loadedModules(compiling: files)
        let banned = loaded.intersection(Self.bannedModules)
        #expect(banned.isEmpty, """
            AuraCore 編譯時載入了禁止的 module：\(banned.sorted().joined(separator: ", "))
            （這次共載入 \(loaded.count) 個 module）
            """)
    }

    /// 正向對照：gate 真的抓得到違規，而不是永遠回報「乾淨」。`import Cocoa` 這個
    /// probe 順便釘住一件容易誤會的事——module trace **不會**出現 `Cocoa` 這個名字
    /// （它是 re-export AppKit 的 Clang module），是靠 `AppKit` 被攔下來的。
    @Test("編譯器 gate 對真違規會紅（正向對照）")
    func compilerGateCatchesViolations() throws {
        for line in ["import AppKit", "import Cocoa", "import SwiftUI"] {
            let loaded = try Self.withTemporaryDirectory { dir -> Set<String> in
                let probe = dir.appendingPathComponent("Probe.swift")
                try "\(line)\npublic enum Probe { public static let v = 1 }\n"
                    .write(to: probe, atomically: true, encoding: .utf8)
                return try Self.loadedModules(compiling: [probe])
            }
            let banned = loaded.intersection(Self.bannedModules)
            #expect(!banned.isEmpty, "gate 沒抓到 `\(line)` —— 解析壞了會讓所有東西看起來都乾淨")
        }
    }

    /// 釘住這個機制**唯一**做得到、掃文字永遠做不到的事：transitive 依賴。
    /// probe 的原始碼全文沒有「AppKit」字樣，只 `import Mid`，而 Mid 內部
    /// `@_exported import AppKit` —— 任何文字 gate 對它必然是綠的。
    @Test("gate 抓得到 transitive 依賴（文字裡沒有 AppKit 也算）")
    func compilerGateCatchesTransitiveDependency() throws {
        let loaded = try Self.withTemporaryDirectory { dir -> Set<String> in
            let mid = dir.appendingPathComponent("Mid.swift")
            try "@_exported import AppKit\npublic enum Mid { public static let v = 1 }\n"
                .write(to: mid, atomically: true, encoding: .utf8)
            let build = Process()
            build.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            build.arguments = ["swiftc", "-emit-module", "-module-name", "Mid",
                               "-target", Self.gateTarget, "-emit-module-path",
                               dir.appendingPathComponent("Mid.swiftmodule").path, mid.path]
            try build.run()
            build.waitUntilExit()
            try #require(build.terminationStatus == 0, "建不出 Mid.swiftmodule，這個對照組就失效了")
            let source = "import Mid\npublic enum Probe { public static let v = Mid.v }\n"
            #expect(!source.contains("AppKit"), "probe 原始碼必須不含 AppKit 字樣，否則證明不了 transitive")
            let probe = dir.appendingPathComponent("Probe.swift")
            try source.write(to: probe, atomically: true, encoding: .utf8)
            return try Self.loadedModules(compiling: [probe], searchPaths: [dir.path])
        }
        #expect(loaded.contains("AppKit"), "transitive 依賴沒被抓到 —— 這是換掉文字 gate 的主要理由")
    }

    /// 反向對照：gate 自己的前提壞掉時必須紅，不准讀成「乾淨」—— 這條 task 反覆
    /// 產生的失敗模式正是 silent degradation。trace 寫不出去（實測 swiftc exit 1）
    /// 與完全沒有輸入檔，兩種前提破壞都必須 throw。
    @Test("gate 前提壞掉時必須紅，不准安靜放行（反向對照）")
    func compilerGateFailsLoudlyWhenBroken() {
        #expect(throws: GateFailure.self, "trace 寫不出來時不能回報乾淨") {
            _ = try Self.loadedModules(compiling: Self.swiftFiles(under: "Sources/AuraCore"),
                                       tracePathOverride: "/nonexistent-\(UUID().uuidString)/trace.json")
        }
        #expect(throws: GateFailure.self, "沒有輸入檔時不能回報乾淨") {
            _ = try Self.loadedModules(compiling: [])
        }
    }

    /// 編譯器 gate 用單獨的 `swiftc` 跑，前提是 AuraCore 沒有 target dependency（否則
    /// 要補 `-I`）。把前提釘在 manifest 上：一旦長出依賴或平台版本調動，這個測試要紅在
    /// 「請補 -I／同步 triple」，而不是讓 gate 安靜地編不動。字串比對對排版敏感，但
    /// 敏感的方向是安全的（改格式會紅，不會靜默放行）。
    @Test("Package.swift 仍撐得住編譯器 gate 的假設")
    func manifestPinsGateAssumptions() throws {
        let manifest = try String(contentsOf: Self.repoRoot().appendingPathComponent("Package.swift"),
                                  encoding: .utf8)
        #expect(manifest.contains(#".target(name: "AuraCore"),"#),
                "AuraCore 有了 target dependency：gate 的 swiftc 需要對應的 -I 路徑")
        #expect(manifest.contains(".macOS(.v13)"),
                "平台最低版本變了：請同步 IsolationTests.gateTarget")
    }

    // MARK: - 檔案長度

    /// 正確算行數：`split(separator: "\n", omittingEmptySubsequences: false).count` 對
    /// 結尾有換行的檔案會多算 1（`"a\nb\n"` → 3），使「≤200」實際擋在 199。改成數換行。
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

    /// 行數上限分層：`Sources/` ≤ 200、`Tests/` ≤ 300 —— 測試檔合理地帶著 fixture
    /// 判讀邏輯，所以給 300，而不是留一個沒寫明的豁免。掃描對象由磁碟推導（`Sources`／
    /// `Tests` 遞迴），新增 module 或 test target 不會靜默逃過上限。
    @Test("Sources 每檔 ≤ 200 行、Tests 每檔 ≤ 300 行")
    func fileLengthLimit() throws {
        for (layer, limit) in [("Sources", 200), ("Tests", 300)] {
            let files = Self.swiftFiles(under: layer)
            #expect(!files.isEmpty, "\(layer) 掃不到任何 .swift —— gate 不能空跑")
            for file in files {
                let lines = Self.lineCount(of: try String(contentsOf: file, encoding: .utf8))
                #expect(lines <= limit, "\(layer)/\(file.lastPathComponent) 有 \(lines) 行，超過 \(limit) 行上限")
            }
        }
    }
}
