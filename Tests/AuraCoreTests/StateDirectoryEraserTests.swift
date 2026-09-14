import Testing
import Foundation
@testable import AuraHookFile

/// T24（`clean-uninstall`）：`StateDirectoryEraser`——完整移除的步驟3（刪 `~/.agentaura`）。
/// 安全界線本身（`isSafeToErase`）獨立驗證，`erase()` 只再驗一次「真的會刪」與「不安全就
/// 完全不碰」。四個安全界線之一（team-lead D-1）：不是我們自己建的東西一律不動。
@Suite("StateDirectoryEraser（T24 D-1 步驟3／D-6）")
struct StateDirectoryEraserTests {

    func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("aura-state-eraser-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    @Test("isSafeToErase：正例——.agentaura 緊接在 home 下、是真的目錄 → true")
    func safeWhenDirectlyUnderHomeAndRealDirectory() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let target = home.appendingPathComponent(".agentaura")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        #expect(StateDirectoryEraser.isSafeToErase(target, home: home) == true)
    }

    @Test("isSafeToErase：最後一段不是 .agentaura → false（即使緊接在 home 下且是目錄）")
    func unsafeWhenLastComponentIsNotDotAgentaura() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let target = home.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        #expect(StateDirectoryEraser.isSafeToErase(target, home: home) == false, """
            使用者自己的 Documents 目錄絕不能被完整移除流程刪掉，即使呼叫端不小心傳錯了 URL
            """)
    }

    @Test("isSafeToErase：.agentaura 是別人某個子目錄底下的同名目錄（不是緊接 home）→ false")
    func unsafeWhenNotDirectlyUnderHome() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let nested = home.appendingPathComponent("Projects/some-repo/.agentaura")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        #expect(StateDirectoryEraser.isSafeToErase(nested, home: home) == false, """
            隨便一個 repo 裡剛好也叫 .agentaura 的目錄不該被當成我們的狀態目錄
            """)
    }

    @Test("isSafeToErase：.agentaura 是 symlink（不是真的目錄）→ false，即使指向的目標存在")
    func unsafeWhenSymlinkNotRealDirectory() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let elsewhere = home.appendingPathComponent("elsewhere-important-data")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try "precious".write(to: elsewhere.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
        let target = home.appendingPathComponent(".agentaura")
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: elsewhere)
        #expect(StateDirectoryEraser.isSafeToErase(target, home: home) == false, """
            .agentaura 被換成指到別處的 symlink 時必須拒絕——遞迴刪除會刪到 symlink 目標，
            而那從結構上就不保證是我們自己建的東西
            """)
    }

    @Test("isSafeToErase：不存在 → false（沒東西可刪，erase() 因此安靜跳過）")
    func unsafeWhenAbsent() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let target = home.appendingPathComponent(".agentaura")
        #expect(StateDirectoryEraser.isSafeToErase(target, home: home) == false)
    }

    @Test("erase()：安全情況下真的刪掉目錄與內容")
    func eraseRemovesRealDirectory() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let target = home.appendingPathComponent(".agentaura")
        try FileManager.default.createDirectory(at: target.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        try "{}".write(to: target.appendingPathComponent("sessions/x.json"), atomically: true, encoding: .utf8)

        StateDirectoryEraser.erase(target, home: home)

        #expect(!FileManager.default.fileExists(atPath: target.path), "erase() 之後 .agentaura 應該完全消失")
    }

    @Test("erase()：跑第二次（已經不存在）不得爆炸，冪等（D-6）")
    func eraseIsIdempotent() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let target = home.appendingPathComponent(".agentaura")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        StateDirectoryEraser.erase(target, home: home)
        StateDirectoryEraser.erase(target, home: home)   // 第二次：已經不存在

        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test("erase()：不安全（symlink）時完全不碰——symlink 本身與它指向的目標都還在")
    func eraseSkipsUnsafeSymlinkEntirely() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let elsewhere = home.appendingPathComponent("elsewhere-important-data")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try "precious".write(to: elsewhere.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
        let target = home.appendingPathComponent(".agentaura")
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: elsewhere)

        StateDirectoryEraser.erase(target, home: home)

        #expect(FileManager.default.fileExists(atPath: target.path), "symlink 本身不該被動到")
        #expect(FileManager.default.fileExists(atPath: elsewhere.appendingPathComponent("keep.txt").path), """
            symlink 指向的真實資料必須完好無缺——這是這條 gate 存在的唯一理由
            """)
    }
}
