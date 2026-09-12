import Testing
import Foundation

/// T01 必辦③的自我測試：用真的 `rename(2)`（不是靠還沒寫的 `Installer`）重現
/// A3 實測的 clobber 情境——把一顆有內容的普通檔案原子替換成指向目錄的 symlink，
/// 驗證 `ClobberAssertionShape` 抓得到「內容消失」且不會誤報成一次未預期的 throw。
/// **這條合理地是 GREEN**：驗的是斷言形狀本身（純 POSIX 呼叫），不是 `Installer`。
@Suite("ClobberAssertionShape 自我驗證")
struct ClobberAssertionShapeTests {

    @Test("rename 蓋掉普通檔案後：Optional<Data> 從有變 nil，lstat 型別從 regularFile 變 symlink")
    func clobberIsDetectedByOptionalDataAndLstatType() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aura-t01-clobber-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let victim = root.appendingPathComponent("skills-agentaura")
        let originalContent = "使用者的原始內容，18 bytes"
        try originalContent.write(to: victim, atomically: true, encoding: .utf8)

        let before = ClobberAssertionShape.contentSnapshot(at: victim)
        let beforeKind = ClobberAssertionShape.entryKind(at: victim)
        #expect(before != nil, "前提：clobber 前應讀得到內容")
        #expect(beforeKind == .regularFile, "前提：clobber 前應是普通檔案")

        // 模擬 §4.1 第 4 步「原子替換」：symlink(bundledPlugin → tmp) → rename(tmp → 目標)。
        // `rename` 不經過 `unlink`，一次都不會問「原本是不是普通檔案」——這正是 S0-1
        // 揭露的毀檔路徑：目標（bundledPlugin）指向一個目錄。
        let bundledPluginDir = root.appendingPathComponent("bundled-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: bundledPluginDir, withIntermediateDirectories: true)
        let tmp = root.appendingPathComponent("tmp-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: tmp, withDestinationURL: bundledPluginDir)
        let rc = rename(tmp.path, victim.path)
        #expect(rc == 0, "前提：rename 本身必須成功（POSIX 允許 rename 蓋掉既有檔案），errno=\(errno)")

        let after = ClobberAssertionShape.contentSnapshot(at: victim)
        let afterKind = ClobberAssertionShape.entryKind(at: victim)

        #expect(after == nil, """
            clobber 後 Optional<Data> 應為 nil（路徑現在是指向目錄的 symlink，讀不出內容），
            實際 \(String(describing: after))
            """)
        #expect(afterKind == .symlink, "clobber 後 lstat 型別應為 symlink，實際 \(afterKind)")
        #expect(before != after, "clobber 前後的 Optional<Data> 必須不相等——這是 G3(a) 要守的斷言")
    }

    @Test("未被 clobber 時：Optional<Data> 相等、lstat 型別不變（負對照）")
    func untouchedFileStaysUnchanged() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aura-t01-clobber-neg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let victim = root.appendingPathComponent("untouched")
        try "content".write(to: victim, atomically: true, encoding: .utf8)

        let before = ClobberAssertionShape.contentSnapshot(at: victim)
        let beforeKind = ClobberAssertionShape.entryKind(at: victim)
        let after = ClobberAssertionShape.contentSnapshot(at: victim)
        let afterKind = ClobberAssertionShape.entryKind(at: victim)

        #expect(before == after, "沒被碰過的檔案，兩次快照應相等——證明斷言形狀不會無中生有地報紅")
        #expect(beforeKind == afterKind && beforeKind == .regularFile)
    }
}
