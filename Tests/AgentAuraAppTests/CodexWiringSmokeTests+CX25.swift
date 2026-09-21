import Testing
import Foundation
@testable import AgentAuraApp

/// CX25 來源掃描半——搬出主檔（`CodexWiringSmokeTests.swift`，撞到 300 行 Tests 上限）。
/// `codexHome` 的生產路徑不得用 `environment["HOME"]`（T04 review M1／M2 同一個陷阱已
/// 出現兩次：`timeout`／`agentFlag`；掃描本身不能拿產生器跟自己比，但這裡驗的是「有沒有
/// 用這個字面」，不是「產生器輸出是否正確」，字面掃描是對的工具）。**只掃 `Sources/`**——
/// `Tests/`／`docs/` 裡出現這個字面是在講這件事，不是在做這件事。
extension CodexWiringSmokeTests {
    @Test("productionCodexHomeIsRealHome 來源掃描：Sources/ 不得用 environment[\"HOME\"] 算 codexHome")
    func productionCodexHomeSourceNeverReadsHomeEnvVar() throws {
        let sourcesRoot = Self.repoRoot().appendingPathComponent("Sources")
        let offenders = Self.swiftFiles(under: sourcesRoot).compactMap { url -> String? in
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  text.contains("environment[\"HOME\"]") else { return nil }
            return url.lastPathComponent
        }
        #expect(offenders.isEmpty, """
            \(offenders) 用了 environment["HOME"] 算路徑——codexHome／claudeHome 都必須用
            FileManager.default.homeDirectoryForCurrentUser，不是環境變數（CX25）
            """)
    }

    /// 同一個 target 看不到 `Tests/AuraCoreTests/Gate.swift`，各自維護一份小型
    /// `repoRoot()`（同 `AboutContentTests` 的既有先例）。
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

    static func swiftFiles(under root: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
