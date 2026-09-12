import Testing
import Foundation
import AuraCore
import AuraHookFile
@testable import AgentAuraApp

/// mutation 7（T07 report）：`Installer` 的 stamp 若把 `st_mtimespec`（秒＋奈秒）
/// 降級成 `st_mtime`（僅秒），兩顆「同一整秒內以不同內容重建」的 hook 二進位會拿到
/// **相同**的 stamp——`HookVerificationStore` 就會把「從沒驗過的新內容」誤判成 `.verified`，
/// 正是 T01 必辦④要防的「`.verified` 但從沒驗過這一份」。
///
/// 用 `utimensat` 直接釘死 mtime 的秒與奈秒欄位，不依賴真的寫檔時序——避免測試恰好跨秒邊界
/// 而讓這條 gate 偶爾失去辨別力（deterministic，不是機率性通過）。
@Suite("Installer stamp 對 mtime 奈秒精度敏感（mutation 7）")
struct HookVerificationStampPrecisionTests {
    static let suiteName = "io.agentaura.tests.mtime-precision"

    func setModificationTime(of url: URL, seconds: Int, nanoseconds: Int) throws {
        var times = [
            timespec(tv_sec: seconds, tv_nsec: 0),
            timespec(tv_sec: seconds, tv_nsec: nanoseconds),
        ]
        let rc = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return utimensat(AT_FDCWD, path, &times, 0)
        }
        #expect(rc == 0, "utimensat 失敗（errno=\(errno)），前提步驟本身就壞了")
    }

    @MainActor
    @Test("同一整秒、不同奈秒的兩份 hook 二進位：stamp 必須不同，舊憑證不得對新內容回 .verified")
    func stampDistinguishesSameSecondRebuild() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aura-mtime-precision-\(UUID().uuidString)")
        let claudeHome = root.appendingPathComponent("claudeHome")
        let pluginDir = root.appendingPathComponent("plugin")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: claudeHome.appendingPathComponent("skills"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pluginDir.appendingPathComponent("hooks"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pluginDir.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try "{}".write(to: pluginDir.appendingPathComponent("hooks/hooks.json"), atomically: true, encoding: .utf8)
        // 非 atomic 寫入（`Data.write(to:)` 預設 options，不是 `.atomic`）：`atomically: true`
        // 的字串寫入是「寫臨時檔再 rename」，會換一顆新 inode，讓下面「同一顆檔案重建」
        // 的前提（dev/ino 不變、只有 mtime／內容變）失真——這是本測試踩過的第一版 bug。
        let hookBinary = pluginDir.appendingPathComponent("bin/aura-hook")
        try Data("v1".utf8).write(to: hookBinary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookBinary.path)
        try FileManager.default.createSymbolicLink(
            at: claudeHome.appendingPathComponent("skills/agentaura"), withDestinationURL: pluginDir)

        let installer = AppInstallerFixture.installer(claudeHome: claudeHome, bundlePluginURL: pluginDir)
        let fixedSecond = 1_700_000_000   // 任意固定整秒，兩次寫入共用同一個秒值

        try setModificationTime(of: hookBinary, seconds: fixedSecond, nanoseconds: 111_111_111)
        let stamp1 = try #require(installer.probe().hookBinaryStamp)

        let defaults = try #require(UserDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        let store = HookVerificationStore(defaults: defaults)
        store.writeVerified(stamp1)
        #expect(store.verification(for: stamp1) == .verified, "前提：寫入的憑證應能對得上自己")

        // 同一顆檔案「重建」（同 inode，非 atomic 覆寫）：內容變了、mtime 秒釘死成同一個值，
        // 只有奈秒不同。
        try Data("v2-different-content".utf8).write(to: hookBinary)
        try setModificationTime(of: hookBinary, seconds: fixedSecond, nanoseconds: 222_222_222)
        let stamp2 = try #require(installer.probe().hookBinaryStamp)

        #expect(stamp2 != stamp1, """
            兩份內容不同、mtime 同一整秒但奈秒不同的 hook 二進位，stamp 必須不同——
            若 Installer 把 mtime 降級成只取秒（st_mtime），這裡會相等
            """)
        #expect(store.verification(for: stamp2) != .verified, """
            新內容的 stamp 不該命中舊憑證，實際回報 \(store.verification(for: stamp2))——
            這正是「.verified 但從沒驗過這一份」（T01 必辦④要防的狀態）
            """)
    }
}
