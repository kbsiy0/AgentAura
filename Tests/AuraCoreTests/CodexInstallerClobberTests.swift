import Testing
import Foundation
import AuraCore
@testable import AuraHookFile

/// T06：`CodexInstaller.connect` 拒絕覆寫——CX15（佔用形狀）／CX32（路徑 guard）
/// （spec §4.4／§6.1(3)(4)／§6.3）。
@Suite("CodexInstaller 拒絕覆寫（CX15／CX32）")
struct CodexInstallerClobberTests {

    private let hookBinaryPath = "/Applications/AgentAura.app/Contents/MacOS/aura-hook"

    // MARK: - CX15 codexConnectRefusesEveryOccupiedShape

    /// r4 M1 最關鍵的一格：`hooks.json` 是指向 `config.toml` 的 symlink——連上去絕不能
    /// 覆蓋使用者的 Codex 設定檔。四種形狀**定義域從 `CodexHomeFixture.Shape` 推導**
    /// （T01 review 的既有理由：寫死格數會在漏掉一格時靜默全綠）。
    private static let occupiedShapes: [CodexHomeFixture.Shape] = [
        .hooksJSONIsRegularFile, .hooksJSONIsDirectory,
        .hooksJSONIsSymlinkToConfigToml, .hooksJSONIsDanglingSymlink,
    ]

    @Test("CX15：四種佔用形狀 connect() 一律 throw .alreadyExists，且整棵樹零差異（含 symlink 指向 config.toml 那格）",
          arguments: Self.occupiedShapes)
    func codexConnectRefusesEveryOccupiedShape(_ shape: CodexHomeFixture.Shape) throws {
        let layout = try CodexHomeFixture.make(shape)
        defer { layout.cleanup() }
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)
        let before = DirectoryTreeSnapshot.take(root: layout.codexHome)

        #expect(throws: CodexFailure.alreadyExists) {
            try codexInstaller.connect(json: CodexHooksJSON.json(hookBinaryPath: hookBinaryPath),
                                  translocated: false, inDownloads: false)
        }

        let after = DirectoryTreeSnapshot.take(root: layout.codexHome)
        let delta = DirectoryTreeSnapshot.changedPaths(before: before, after: after)
        #expect(delta.isEmpty, """
            \(shape) 形狀下 connect() 必須整棵樹零差異（含 hooks.json 自己與它可能指向的
            config.toml）；實際差異：\(delta.sorted())
            """)
    }

    /// D-q 附帶：> 64 KiB 的垃圾也是「已存在」，`O_EXCL` 不看內容不看大小，
    /// 一樣是 EEXIST——同一條 guard，不是另一個分支。
    @Test("CX15 附帶：> 64 KiB 的垃圾一樣 throw .alreadyExists 且不被覆寫")
    func codexConnectRefusesOversizedGarbageToo() throws {
        let layout = try CodexHomeFixture.make(.hooksJSONIsGarbageOver64KiB)
        defer { layout.cleanup() }
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)
        let before = try Data(contentsOf: layout.codexHome.appendingPathComponent("hooks.json"))

        #expect(throws: CodexFailure.alreadyExists) {
            try codexInstaller.connect(json: CodexHooksJSON.json(hookBinaryPath: hookBinaryPath),
                                  translocated: false, inDownloads: false)
        }
        let after = try Data(contentsOf: layout.codexHome.appendingPathComponent("hooks.json"))
        #expect(before == after)
    }

    // MARK: - CX32 codexConnectRefusesBlockedBundlePath

    @Test("CX32：translocated 時 connect() throw .mustMoveToApplications，整棵樹零差異")
    func codexConnectRefusesTranslocated() throws {
        let layout = try CodexHomeFixture.make(.codexHomeIsEmptyDirectory)
        defer { layout.cleanup() }
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)
        let before = DirectoryTreeSnapshot.take(root: layout.codexHome)

        #expect(throws: CodexFailure.mustMoveToApplications) {
            try codexInstaller.connect(json: CodexHooksJSON.json(hookBinaryPath: hookBinaryPath),
                                  translocated: true, inDownloads: false)
        }
        let after = DirectoryTreeSnapshot.take(root: layout.codexHome)
        #expect(DirectoryTreeSnapshot.changedPaths(before: before, after: after).isEmpty)
    }

    @Test("CX32：inDownloads 時 connect() throw .mustMoveToApplications，整棵樹零差異")
    func codexConnectRefusesInDownloads() throws {
        let layout = try CodexHomeFixture.make(.codexHomeIsEmptyDirectory)
        defer { layout.cleanup() }
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)
        let before = DirectoryTreeSnapshot.take(root: layout.codexHome)

        #expect(throws: CodexFailure.mustMoveToApplications) {
            try codexInstaller.connect(json: CodexHooksJSON.json(hookBinaryPath: hookBinaryPath),
                                  translocated: false, inDownloads: true)
        }
        let after = DirectoryTreeSnapshot.take(root: layout.codexHome)
        #expect(DirectoryTreeSnapshot.changedPaths(before: before, after: after).isEmpty)
    }

    @Test("CX32：hook 路徑含空白時 connect() throw .unsupportedPathCharacter(\" \")，整棵樹零差異")
    func codexConnectRefusesPathContainingSpace() throws {
        let layout = try CodexHomeFixture.make(.codexHomeIsEmptyDirectory)
        defer { layout.cleanup() }
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)
        let before = DirectoryTreeSnapshot.take(root: layout.codexHome)
        let spacedPath = "/Applications/Agent Aura.app/Contents/MacOS/aura-hook"

        #expect(throws: CodexFailure.unsupportedPathCharacter(" ")) {
            try codexInstaller.connect(json: CodexHooksJSON.json(hookBinaryPath: spacedPath),
                                  translocated: false, inDownloads: false)
        }
        let after = DirectoryTreeSnapshot.take(root: layout.codexHome)
        #expect(DirectoryTreeSnapshot.changedPaths(before: before, after: after).isEmpty)
    }

    @Test("CX32：乾淨路徑（負對照）connect() 必須成功，證明 guard 沒有誤擋")
    func codexConnectSucceedsOnCleanPath() throws {
        let layout = try CodexHomeFixture.make(.codexHomeIsEmptyDirectory)
        defer { layout.cleanup() }
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)

        _ = try codexInstaller.connect(json: CodexHooksJSON.json(hookBinaryPath: hookBinaryPath),
                                  translocated: false, inDownloads: false)
        #expect(FileManager.default.fileExists(
            atPath: layout.codexHome.appendingPathComponent("hooks.json").path))
    }
}
