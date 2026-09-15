import Testing
import Foundation
@testable import AgentAuraApp
import AuraCore

/// T25：`recycler.recycle` 的 completion 曾經把 `Error?` 整個吞掉——app 已經走完視覺上的
/// 「完整移除」，垃圾桶動作卻可能沒有真的落地，而且完全沒有留下任何線索（真機事故：
/// app 從 `/Applications` 消失，`~/.Trash` 沒有它，全機 `find`／`mdfind` 都找不到）。
/// 這裡直接測 `UninstallFailureLog.record` 本身（不經過整個 `Uninstaller.run()` 的
/// 非同步流程）：內容格式、以及覆蓋而非累加——同一台機器只在乎「上一次」有沒有失敗，
/// 累加只會讓這個診斷檔自己變成需要輪替的新問題。
@Suite("UninstallFailureLog（T25）")
struct UninstallFailureLogTests {

    struct FakeError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("UninstallFailureLogTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    @Test("record：寫入的內容含來源路徑與錯誤描述")
    func recordWritesSourceAndErrorDescription() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let source = URL(fileURLWithPath: "/Applications/AgentAura.app")

        UninstallFailureLog.record(error: FakeError(message: "磁碟空間不足"), source: source, home: home,
                                   language: .traditionalChinese)

        let logURL = home.appendingPathComponent(UninstallFailureLog.filename)
        let content = try String(contentsOf: logURL, encoding: .utf8)
        #expect(content.contains(source.path), "應該包含來源路徑")
        #expect(content.contains("磁碟空間不足"), "應該包含錯誤描述")
    }

    @Test("record 呼叫兩次：第二次覆蓋第一次，不是累加")
    func recordOverwritesRatherThanAppends() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let source = URL(fileURLWithPath: "/Applications/AgentAura.app")

        UninstallFailureLog.record(error: FakeError(message: "第一次錯誤"), source: source, home: home,
                                   language: .traditionalChinese)
        UninstallFailureLog.record(error: FakeError(message: "第二次錯誤"), source: source, home: home,
                                   language: .traditionalChinese)

        let logURL = home.appendingPathComponent(UninstallFailureLog.filename)
        let content = try String(contentsOf: logURL, encoding: .utf8)
        #expect(!content.contains("第一次錯誤"), "不該累加舊紀錄")
        #expect(content.contains("第二次錯誤"))
    }

    /// T29（i18n）：英文那半——同一個 `record`，換語言就換文字，不是寫死中文格式。
    @Test("record：language 為 .english 時寫入英文格式的紀錄行")
    func recordWritesEnglishWhenLanguageIsEnglish() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let source = URL(fileURLWithPath: "/Applications/AgentAura.app")

        UninstallFailureLog.record(error: FakeError(message: "disk full"), source: source, home: home,
                                   language: .english)

        let logURL = home.appendingPathComponent(UninstallFailureLog.filename)
        let content = try String(contentsOf: logURL, encoding: .utf8)
        #expect(content.contains(source.path), "應該包含來源路徑")
        #expect(content.contains("disk full"), "應該包含錯誤描述")
        #expect(content.contains("Trash operation failed"), "應該是英文格式，不是中文的「垃圾桶動作失敗」")
        #expect(!content.contains("垃圾桶動作失敗"), "language 為 .english 時不該混進中文")
    }
}
