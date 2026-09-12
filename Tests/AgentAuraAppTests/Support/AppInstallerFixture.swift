import Foundation
import AuraHookFile

/// T08：composition-root 測試共用 fixture——一個乾淨的 `claudeHome` ＋一個「合法」的
/// bundle plugin 目錄（`hooks/hooks.json` ＋ `bin/aura-hook`）。與
/// `Tests/AuraCoreTests/Support/InstallerFixture.swift` 同一個形狀（AgentAuraAppTests
/// 不依賴 AuraCoreTests target，不能直接沿用，本檔是同一個手法的獨立小型複製）。
enum AppInstallerFixture {
    struct Layout {
        let root: URL
        let claudeHome: URL
        let bundlePlugin: URL
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    /// T10b：測試一律走這裡建 `Installer`，**不要直接呼叫 `Installer(claudeHome:…)`**——
    /// 理由與 `Tests/AuraCoreTests/Support/InstallerFixture.swift` 的同名工廠一致（AgentAuraAppTests
    /// 不依賴 AuraCoreTests target，不能直接沿用，本函式是同一個手法的獨立小型複製）。
    static func installer(claudeHome: URL, bundlePluginURL: URL,
                          verificationRootOverride: URL? = nil,
                          verificationTimeout: Double = 5) -> Installer {
        Installer(claudeHome: claudeHome, bundlePluginURL: bundlePluginURL,
                  verificationRootOverride: verificationRootOverride,
                  verificationTimeout: verificationTimeout)
    }

    enum FixtureError: Error { case binaryMissing }

    /// 找出 `swift build` 產出的真 `aura-hook`（同 `AuraHookCLITests.binaryURL()` 的手法）。
    static func realHookBinaryURL() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        while dir.pathComponents.count > 1 {
            dir = dir.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) { break }
        }
        for config in ["debug", "release"] {
            let url = dir.appendingPathComponent(".build/\(config)/aura-hook")
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        throw FixtureError.binaryMissing
    }

    private static func skeleton(name: String) throws -> Layout {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aura-app-installer-fixture-\(name)-\(UUID().uuidString)")
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

    /// 真的 SwiftPM 產物——exec 驗證會真的寫出狀態檔 → `.verified`。
    static func make() throws -> Layout {
        let layout = try skeleton(name: "verified")
        let realBinary = try realHookBinaryURL()
        let dest = layout.bundlePlugin.appendingPathComponent("bin/aura-hook")
        try FileManager.default.copyItem(at: realBinary, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        return layout
    }

    /// 有 x 位、真的能跑，但不寫任何狀態檔就結束——模擬 quarantine SIGKILL 的外部可觀察結果
    /// → `.hookBlockedOrBroken`。不需要真的二進位，任何機器都能跑。
    static func makeWithSilentHookBinary() throws -> Layout {
        let layout = try skeleton(name: "silent")
        let dest = layout.bundlePlugin.appendingPathComponent("bin/aura-hook")
        try "#!/bin/sh\nexit 137\n".write(to: dest, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        return layout
    }

    /// 有 x 位但不是合法可執行格式——`Process.run()` 本身會 throw（ENOEXEC）→ `.hookUnconfirmed`。
    static func makeWithUnexecutableGarbageBinary() throws -> Layout {
        let layout = try skeleton(name: "garbage")
        let dest = layout.bundlePlugin.appendingPathComponent("bin/aura-hook")
        try Data((0..<64).map { _ in UInt8.random(in: 0...255) }).write(to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        return layout
    }

    /// 有 x 位、真的能跑，但跑超過有界等待才結束——模擬機器睡眠等造成的逾時 → `.hookUnconfirmed`
    /// （逾時那一半，與 spawn 丟錯不同代碼路徑，但寫回同一種結果）。呼叫端要注入一個很短的
    /// `Installer.verificationTimeout`，不必真的等好幾秒。
    static func makeWithSlowHookBinary() throws -> Layout {
        let layout = try skeleton(name: "slow")
        let dest = layout.bundlePlugin.appendingPathComponent("bin/aura-hook")
        try "#!/bin/sh\nsleep 5\nexit 0\n".write(to: dest, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        return layout
    }

    /// 建好 fixture 之後直接把它接上（`symlink(bundlePlugin → claudeHome/skills/agentaura)`）
    /// ——省下每個測試自己重打一次 `connect()` 只為了建立「已接上」的前提。
    static func linkDirectly(_ layout: Layout) throws {
        let skills = layout.claudeHome.appendingPathComponent("skills")
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: skills.appendingPathComponent("agentaura"), withDestinationURL: layout.bundlePlugin)
    }
}
