import Testing
import Foundation

/// 跨層 gate 的共用機制。**不是 `@Suite`** —— 它只是一組工具，
/// 由 `IsolationTests` 與 `FileLengthTests` 兩個 suite 共用。
///
/// 抽出來的理由很無聊但很實際：合在一起是 315 行，超過測試檔 300 行的上限，
/// 而那個上限正是這份檔案裡的 `fileLengthLimit` 在把關的 —— gate 自己違規。
enum Gate {
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

    /// **UI 允許清單。** 只有這裡列出的 target 可以載入 AppKit / SwiftUI。
    static let uiTargets: Set<String> = ["AgentAuraApp"]

    /// 非 UI 的 target，依依賴順序（後者可依賴前者）。
    ///
    /// 依賴順序無法從磁碟推導，所以這一份是手寫的 —— 但
    /// `nonUITargetsLoadNoUIModules` 會斷言「這份清單 ∪ `uiTargets` 必須等於
    /// `Sources/` 下的實際目錄集合」，所以新增一個 target 不會靜默逃過 gate，
    /// 只會紅在「請把它加進清單並排好順序」。
    static let nonUITargetsInDependencyOrder = ["AuraCore", "AuraHookFile", "aura-hook"]

    /// 建出 `<name>.swiftmodule` 供後續 target 的 `-I` 使用。
    static func emitModule(named name: String, files: [URL], into dir: URL) throws {
        let moduleName = name.replacingOccurrences(of: "-", with: "_")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["swiftc", "-emit-module", "-module-name", moduleName,
                          "-target", gateTarget, "-I", dir.path,
                          "-emit-module-path", dir.appendingPathComponent("\(moduleName).swiftmodule").path]
                       + files.map(\.path)
        let pipe = Pipe(); task.standardError = pipe; task.standardOutput = pipe
        try task.run()
        let err = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw GateFailure("建不出 \(moduleName).swiftmodule，後續 target 的 gate 就編不動：\(err)")
        }
    }

    /// 正確算行數：`split(separator: "\n", omittingEmptySubsequences: false).count` 對
    /// 結尾有換行的檔案會多算 1（`"a\nb\n"` → 3），使「≤200」實際擋在 199。改成數換行。
    static func lineCount(of text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let newlines = text.reduce(into: 0) { acc, ch in if ch == "\n" { acc += 1 } }
        return text.hasSuffix("\n") ? newlines : newlines + 1
    }

    // MARK: - 平台契約：從 `swift package dump-package` 推導，不比對原始文字

    struct PackageTarget {
        let name: String
        let type: String            // regular / executable / test
        let dependencies: [String]
    }

    /// 解析 `swift package dump-package`。
    ///
    /// 比對 `Package.swift` 的**原始文字**對排版敏感，而且答不出依賴關係。
    /// SwiftPM 自己就提供了結構化輸出 —— 平台給了契約就用契約。
    static func packageTargets() throws -> [PackageTarget] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        // **必須用獨立的 `--scratch-path`。**
        //
        // `swift test` 執行期間持有這個 package 的 SwiftPM 鎖；測試裡再開一個
        // 用預設 `.build` 的 `swift package` 子行程會永遠等下去（實測：180s 逾時強殺）。
        // 給它一個自己的 scratch 目錄就不會碰到那把鎖。
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("aura-dump-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        task.arguments = ["swift", "package", "--scratch-path", scratch.path, "dump-package"]
        task.currentDirectoryURL = repoRoot()
        let pipe = Pipe(); task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw GateFailure("swift package dump-package 失敗（exit \(task.terminationStatus)）—— gate 無法作答")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["targets"] as? [[String: Any]], !raw.isEmpty else {
            throw GateFailure("dump-package 解析不出 targets —— 空結果不能讀成「乾淨」")
        }
        return raw.map { t in
            let deps = (t["dependencies"] as? [[String: Any]] ?? []).compactMap { d -> String? in
                (d["byName"] as? [Any])?.first as? String ?? (d["target"] as? [Any])?.first as? String
            }
            return PackageTarget(name: t["name"] as? String ?? "?",
                                 type: t["type"] as? String ?? "?",
                                 dependencies: deps)
        }
    }

    /// `Sources/` 下的非測試 target，依依賴拓撲排序（被依賴者在前）。
    ///
    /// 先前這是一份**手寫**的順序清單。依賴順序其實在 `Package.swift` 裡就有，
    /// 只是要問對人 —— `dump-package` 給得出來，那就不該手維護。
    static func nonTestTargetsInDependencyOrder() throws -> [String] {
        let targets = try packageTargets().filter { $0.type != "test" }
        let byName = Dictionary(uniqueKeysWithValues: targets.map { ($0.name, $0) })
        var out: [String] = []
        var visiting: Set<String> = []
        func visit(_ name: String) throws {
            guard !out.contains(name) else { return }
            guard !visiting.contains(name) else { throw GateFailure("target 依賴有環：\(name)") }
            visiting.insert(name)
            for d in byName[name]?.dependencies ?? [] where byName[d] != nil { try visit(d) }
            visiting.remove(name)
            out.append(name)
        }
        for t in targets.map(\.name).sorted() { try visit(t) }
        return out
    }

    // MARK: - 白名單基準：不列名單，當場算

    /// 只 `import` 指定 module 的 probe 會載入哪些 module —— 那就是那一層的閉包。
    ///
    /// 為什麼不寫死一份白名單：白名單會隨工具鏈 drift，升級 Swift 就誤紅，
    /// 而一個會為了無關原因變紅的 gate，很快就會被當成雜訊忽略。
    /// 基準線在測試時用**同一套工具鏈**算出來，所以只有真正多出來的東西會被抓到。
    static func baselineModules(importing imports: [String]) throws -> Set<String> {
        try withTemporaryDirectory { dir in
            let probe = dir.appendingPathComponent("Baseline.swift")
            let src = imports.map { "import \($0)" }.joined(separator: "\n")
                + "\npublic enum Baseline { public static let v = 1 }\n"
            try src.write(to: probe, atomically: true, encoding: .utf8)
            return try loadedModules(compiling: [probe])
        }
    }

    /// 編譯器內部產物，不是框架依賴。
    ///
    /// `SwiftOnoneSupport` 來自用 `-Onone` 建出來的依賴 `.swiftmodule`
    /// （實測：不加 `-I` 的 probe 不會產生它，加了才會）。把它列在這裡是
    /// 一個**明確且極小**的例外，不是「反正多出來的都放行」。
    static let compilerInternalModules: Set<String> = ["SwiftOnoneSupport"]
}
