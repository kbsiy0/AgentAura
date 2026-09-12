import Foundation
import AuraHookFile

/// T03 測試共用 fixture：一個乾淨的 `claudeHome` ＋一個「合法」的 bundle plugin 目錄
/// （`hooks/hooks.json` ＋ `bin/aura-hook`）。四種 `bin/aura-hook` 對應 exec 驗證的四種
/// 結果，同一份骨架只換那一顆檔案——G2／G3／G4 共用。
enum InstallerFixture {
    struct Layout {
        let root: URL
        let claudeHome: URL
        let bundlePlugin: URL
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    /// T10b：測試一律走這裡建 `Installer`，**不要直接呼叫 `Installer(claudeHome:…)`**——
    /// 生產預設的 `verificationTimeout: 2`（秒）在全套件並行下會偶發撞到（實測
    /// `InstallerPathScopeTests` `failed after 2.051 seconds`，`.hookUnconfirmed`），
    /// 而那條路徑真的會 spawn `aura-hook` 行程搶資源。逾時本身的 gate（`verificationTimeout:
    /// 0.05` 那條）反過來自己注入很小的值，不受這個預設影響。
    /// 簽名刻意跟 `Installer.init` 同一組參數名，呼叫端只差開頭一個 `InstallerFixture.` 前綴。
    static func installer(claudeHome: URL, bundlePluginURL: URL,
                          verificationRootOverride: URL? = nil,
                          verificationTimeout: Double = 5) -> Installer {
        Installer(claudeHome: claudeHome, bundlePluginURL: bundlePluginURL,
                  verificationRootOverride: verificationRootOverride,
                  verificationTimeout: verificationTimeout)
    }

    private static func skeleton(name: String) throws -> Layout {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aura-installer-fixture-\(name)-\(UUID().uuidString)")
        let claudeHome = root.appendingPathComponent("claudeHome")
        let bundlePlugin = root.appendingPathComponent("bundlePlugin")
        try FileManager.default.createDirectory(at: claudeHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: bundlePlugin.appendingPathComponent("hooks"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: bundlePlugin.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try "{}".write(to: bundlePlugin.appendingPathComponent("hooks/hooks.json"),
                       atomically: true, encoding: .utf8)
        return Layout(root: root, claudeHome: claudeHome, bundlePlugin: bundlePlugin)
    }

    /// 真的 SwiftPM 產物（`AuraHookCLITests.binaryURL()`）——exec 驗證會真的寫出狀態檔
    /// → `.verified`。G2／G3 的「成功接上」與 G4(b) 共用同一顆二進位。
    static func make() throws -> Layout {
        let layout = try skeleton(name: "verified")
        let realBinary = try AuraHookCLITests.binaryURL()
        let dest = layout.bundlePlugin.appendingPathComponent("bin/aura-hook")
        try FileManager.default.copyItem(at: realBinary, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        return layout
    }

    /// 有 x 位、真的能跑，但**不寫任何狀態檔就結束**——模擬 quarantine SIGKILL／
    /// arch 不符的外部可觀察結果（不必真的重現 SIGKILL 本身）→ `.hookBlockedOrBroken`。
    static func makeWithSilentHookBinary() throws -> Layout {
        let layout = try skeleton(name: "silent")
        let dest = layout.bundlePlugin.appendingPathComponent("bin/aura-hook")
        try "#!/bin/sh\nexit 137\n".write(to: dest, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        return layout
    }

    /// 有 x 位但不是合法可執行格式（隨機位元組，沒有 shebang）——`exec` 本身失敗，
    /// `Process.run()` 會 throw（ENOEXEC）→ `.hookUnconfirmed`（spawn 本身丟錯那一半）。
    static func makeWithUnexecutableGarbageBinary() throws -> Layout {
        let layout = try skeleton(name: "garbage")
        let dest = layout.bundlePlugin.appendingPathComponent("bin/aura-hook")
        try Data((0..<64).map { _ in UInt8.random(in: 0...255) })
            .write(to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        return layout
    }

    /// 有 x 位、真的能跑，但跑超過 2 秒的有界等待才結束——模擬機器睡眠等造成的逾時
    /// → `.hookUnconfirmed`（逾時那一半，與 spawn 丟錯不同代碼路徑，但寫回同一種結果）。
    static func makeWithSlowHookBinary() throws -> Layout {
        let layout = try skeleton(name: "slow")
        let dest = layout.bundlePlugin.appendingPathComponent("bin/aura-hook")
        try "#!/bin/sh\nsleep 5\nexit 0\n".write(to: dest, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        return layout
    }
}
