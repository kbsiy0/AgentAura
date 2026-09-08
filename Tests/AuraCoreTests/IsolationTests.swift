import Testing
import Foundation

@Suite("跨層隔離約束")
struct IsolationTests {

    @Test("除 UI target 外，Sources/ 下每個 target 都不得載入 AppKit / SwiftUI / Cocoa")
    func nonUITargetsLoadNoUIModules() throws {
        let sources = Gate.repoRoot().appendingPathComponent("Sources")
        let dirs = Set(((try? FileManager.default.contentsOfDirectory(
                at: sources, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent))
        #expect(!dirs.isEmpty, "Sources/ 下掃不到任何 target 目錄 —— gate 不能空跑")

        // 需要 gate 的集合 = 磁碟現況 − 允許清單。這個方向才是重點：
        // 任何新增的 target 只要沒被明確豁免，就必須出現在順序清單裡，否則紅。
        // （允許清單裡的 target 尚未建立時不會誤紅 —— 減去一個不存在的名字是 no-op。）
        let gated = dirs.subtracting(Gate.uiTargets)
        #expect(Set(Gate.nonUITargetsInDependencyOrder) == gated, """
            需要 gate 的 target 與順序清單不一致 —— 新 target 不得靜默逃過 gate。
            磁碟上需要 gate 卻沒列：\(gated.subtracting(Set(Gate.nonUITargetsInDependencyOrder)).sorted())
            列了卻不存在：\(Set(Gate.nonUITargetsInDependencyOrder).subtracting(gated).sorted())
            """)

        try Gate.withTemporaryDirectory { dir -> Void in
            for target in Gate.nonUITargetsInDependencyOrder {
                let files = Gate.swiftFiles(under: "Sources/\(target)")
                #expect(!files.isEmpty, "\(target) 掃不到原始檔 —— gate 不能空跑")
                let loaded = try Gate.loadedModules(compiling: files, searchPaths: [dir.path])
                let banned = loaded.intersection(Gate.bannedModules)
                #expect(banned.isEmpty, """
                    \(target) 編譯時載入了禁止的 module：\(banned.sorted().joined(separator: ", "))
                    （這次共載入 \(loaded.count) 個 module）
                    """)
                // executable target 沒有人依賴它，不需要 emit module
                if target != Gate.nonUITargetsInDependencyOrder.last {
                    try Gate.emitModule(named: target, files: files, into: dir)
                }
            }
        }
    }

    /// **豁免必須被賺到。**
    ///
    /// `uiTargets` 是一份手寫的允許清單，而允許清單的危險是：把一個純邏輯 module
    /// 改名成清單上的名字，就能靜默取得豁免。所以反過來驗 —— 被豁免的 target
    /// **必須真的載入 AppKit 或 SwiftUI**，否則它根本不需要豁免，應該回到 gate 裡。
    ///
    /// 尚未建立的 target 不會誤紅（沒有原始檔就跳過），但一旦建立就必須名符其實。
    @Test("UI 允許清單裡的 target 必須真的是 UI target")
    func uiExemptionsAreEarned() throws {
        try Gate.withTemporaryDirectory { dir -> Void in
        for target in Gate.uiTargets.sorted() {
            // 排除 `main.swift`：它的 top-level code 在 SwiftPM 之外用裸 swiftc
            // -typecheck 跑會踩到「call to main actor-isolated initializer in a
            // synchronous nonisolated context」—— 那是 gate 的呼叫方式造成的，
            // 不是被測程式碼的問題。判斷「這個 target 是不是 UI」不需要它。
            let files = Gate.swiftFiles(under: "Sources/\(target)")
                .filter { $0.lastPathComponent != "main.swift" }
            guard !files.isEmpty else { continue }   // 還沒建立
            // UI target 依賴前面那些 module，先建出來供 -I 使用
            for dep in Gate.nonUITargetsInDependencyOrder
            where dep != Gate.nonUITargetsInDependencyOrder.last {
                try Gate.emitModule(named: dep, files: Gate.swiftFiles(under: "Sources/\(dep)"), into: dir)
            }
            let loaded = try Gate.loadedModules(compiling: files, searchPaths: [dir.path])
            #expect(!loaded.intersection(Gate.bannedModules).isEmpty, """
                \(target) 被列在 uiTargets 豁免清單裡，但它一個 UI module 都沒載入 ——
                它不需要豁免。把它從 uiTargets 移除、加進 nonUITargetsInDependencyOrder。
                （允許清單的危險是「改個名字就能繞過 gate」，這條測試堵的是那個。）
                """)
        }
        }
    }

    /// 正向對照：gate 真的抓得到違規，而不是永遠回報「乾淨」。`import Cocoa` 這個
    /// probe 順便釘住一件容易誤會的事——module trace **不會**出現 `Cocoa` 這個名字
    /// （它是 re-export AppKit 的 Clang module），是靠 `AppKit` 被攔下來的。
    @Test("編譯器 gate 對真違規會紅（正向對照）")
    func compilerGateCatchesViolations() throws {
        for line in ["import AppKit", "import Cocoa", "import SwiftUI"] {
            let loaded = try Gate.withTemporaryDirectory { dir -> Set<String> in
                let probe = dir.appendingPathComponent("Probe.swift")
                try "\(line)\npublic enum Probe { public static let v = 1 }\n"
                    .write(to: probe, atomically: true, encoding: .utf8)
                return try Gate.loadedModules(compiling: [probe])
            }
            let banned = loaded.intersection(Gate.bannedModules)
            #expect(!banned.isEmpty, "gate 沒抓到 `\(line)` —— 解析壞了會讓所有東西看起來都乾淨")
        }
    }

    /// 釘住這個機制**唯一**做得到、掃文字永遠做不到的事：transitive 依賴。
    /// probe 的原始碼全文沒有「AppKit」字樣，只 `import Mid`，而 Mid 內部
    /// `@_exported import AppKit` —— 任何文字 gate 對它必然是綠的。
    @Test("gate 抓得到 transitive 依賴（文字裡沒有 AppKit 也算）")
    func compilerGateCatchesTransitiveDependency() throws {
        let loaded = try Gate.withTemporaryDirectory { dir -> Set<String> in
            let mid = dir.appendingPathComponent("Mid.swift")
            try "@_exported import AppKit\npublic enum Mid { public static let v = 1 }\n"
                .write(to: mid, atomically: true, encoding: .utf8)
            let build = Process()
            build.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            build.arguments = ["swiftc", "-emit-module", "-module-name", "Mid",
                               "-target", Gate.gateTarget, "-emit-module-path",
                               dir.appendingPathComponent("Mid.swiftmodule").path, mid.path]
            try build.run()
            build.waitUntilExit()
            try #require(build.terminationStatus == 0, "建不出 Mid.swiftmodule，這個對照組就失效了")
            let source = "import Mid\npublic enum Probe { public static let v = Mid.v }\n"
            #expect(!source.contains("AppKit"), "probe 原始碼必須不含 AppKit 字樣，否則證明不了 transitive")
            let probe = dir.appendingPathComponent("Probe.swift")
            try source.write(to: probe, atomically: true, encoding: .utf8)
            return try Gate.loadedModules(compiling: [probe], searchPaths: [dir.path])
        }
        #expect(loaded.contains("AppKit"), "transitive 依賴沒被抓到 —— 這是換掉文字 gate 的主要理由")
    }

    /// 反向對照：gate 自己的前提壞掉時必須紅，不准讀成「乾淨」—— 這條 task 反覆
    /// 產生的失敗模式正是 silent degradation。trace 寫不出去（實測 swiftc exit 1）
    /// 與完全沒有輸入檔，兩種前提破壞都必須 throw。
    @Test("gate 前提壞掉時必須紅，不准安靜放行（反向對照）")
    func compilerGateFailsLoudlyWhenBroken() {
        #expect(throws: Gate.GateFailure.self, "trace 寫不出來時不能回報乾淨") {
            _ = try Gate.loadedModules(compiling: Gate.swiftFiles(under: "Sources/AuraCore"),
                                       tracePathOverride: "/nonexistent-\(UUID().uuidString)/trace.json")
        }
        #expect(throws: Gate.GateFailure.self, "沒有輸入檔時不能回報乾淨") {
            _ = try Gate.loadedModules(compiling: [])
        }
    }

    /// 編譯器 gate 用單獨的 `swiftc` 跑，前提是 AuraCore 沒有 target dependency（否則
    /// 要補 `-I`）。把前提釘在 manifest 上：一旦長出依賴或平台版本調動，這個測試要紅在
    /// 「請補 -I／同步 triple」，而不是讓 gate 安靜地編不動。字串比對對排版敏感，但
    /// 敏感的方向是安全的（改格式會紅，不會靜默放行）。
    @Test("Package.swift 仍撐得住編譯器 gate 的假設")
    func manifestPinsGateAssumptions() throws {
        let manifest = try String(contentsOf: Gate.repoRoot().appendingPathComponent("Package.swift"),
                                  encoding: .utf8)
        #expect(manifest.contains(#".target(name: "AuraCore"),"#),
                "AuraCore 有了 target dependency：gate 的 swiftc 需要對應的 -I 路徑")
        #expect(manifest.contains(".macOS(.v13)"),
                "平台最低版本變了：請同步 IsolationTests.gateTarget")
    }

    // MARK: - 檔案長度


    @Test("lineCount 對結尾有／無換行都正確")
    func lineCountIsExact() {
        #expect(Gate.lineCount(of: "") == 0)
        #expect(Gate.lineCount(of: "a") == 1)
        #expect(Gate.lineCount(of: "a\n") == 1)
        #expect(Gate.lineCount(of: "a\nb") == 2)
        #expect(Gate.lineCount(of: "a\nb\n") == 2, "結尾換行不得多算一行")
        #expect(Gate.lineCount(of: String(repeating: "x\n", count: 200)) == 200)
    }

    /// 行數上限分層：`Sources/` ≤ 200、`Tests/` ≤ 300 —— 測試檔合理地帶著 fixture
    /// 判讀邏輯，所以給 300，而不是留一個沒寫明的豁免。掃描對象由磁碟推導（`Sources`／
    /// `Tests` 遞迴），新增 module 或 test target 不會靜默逃過上限。
    @Test("Sources 每檔 ≤ 200 行、Tests 每檔 ≤ 300 行")
    func fileLengthLimit() throws {
        for (layer, limit) in [("Sources", 200), ("Tests", 300)] {
            let files = Gate.swiftFiles(under: layer)
            #expect(!files.isEmpty, "\(layer) 掃不到任何 .swift —— gate 不能空跑")
            for file in files {
                let lines = Gate.lineCount(of: try String(contentsOf: file, encoding: .utf8))
                #expect(lines <= limit, "\(layer)/\(file.lastPathComponent) 有 \(lines) 行，超過 \(limit) 行上限")
            }
        }
    }
}
