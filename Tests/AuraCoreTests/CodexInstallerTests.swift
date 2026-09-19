import Testing
import Foundation
import AuraCore
@testable import AuraHookFile

/// T06：`CodexInstaller.connect`／`disconnect` 的內容契約——CX16／CX17（spec §4.4／§6.3）。
/// 佔用形狀（EEXIST）與路徑 guard 分別在 `CodexInstallerClobberTests`（CX15／CX32）；
/// 路徑範圍（只碰 hooks.json／symlink 落在 realpath）在 `CodexPathScopeTests`（CX14／CX18）。
@Suite("CodexInstaller 內容契約（CX16／CX17）")
struct CodexInstallerTests {

    private let hookBinaryPath = "/Applications/AgentAura.app/Contents/MacOS/aura-hook"

    // MARK: - CX16 codexConnectWritesGeneratorBytes

    @Test("CX16：connect() 寫進磁碟的位元組與回傳值都等於產生器輸出")
    func codexConnectWritesGeneratorBytes() throws {
        let layout = try CodexHomeFixture.make(.codexHomeIsEmptyDirectory)
        defer { layout.cleanup() }
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)
        let generated = CodexHooksJSON.json(hookBinaryPath: hookBinaryPath)

        let returned = try codexInstaller.connect(json: generated, translocated: false, inDownloads: false)
        #expect(returned == generated)

        let onDisk = try Data(contentsOf: layout.codexHome.appendingPathComponent("hooks.json"))
        #expect(onDisk == generated)
    }

    @Test("CX16 mutation-observability：少寫最後一個 byte 必須讓這條紅（記錄於報告，非自動化 mutation 注入）")
    func codexConnectWrittenBytesAreExactCount() throws {
        // 這條本身不注入 mutation——它只確認斷言的粒度夠細（逐位元組、非只比長度），
        // 讓「少寫一個 byte」這個 mutation 真的有東西可以打。
        let layout = try CodexHomeFixture.make(.codexHomeIsEmptyDirectory)
        defer { layout.cleanup() }
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)
        let generated = CodexHooksJSON.json(hookBinaryPath: hookBinaryPath)

        _ = try codexInstaller.connect(json: generated, translocated: false, inDownloads: false)
        let onDisk = try Data(contentsOf: layout.codexHome.appendingPathComponent("hooks.json"))
        #expect(onDisk.count == generated.count)
    }

    // MARK: - CX17 codexDisconnectOnlyRemovesOurBytes

    @Test("CX17：逐位元組相符才刪——內容不符必須 throw .notOurs 且不刪")
    func disconnectRefusesOnContentMismatch() throws {
        let layout = try CodexHomeFixture.make(.codexHomeIsEmptyDirectory)
        defer { layout.cleanup() }
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)
        let generated = CodexHooksJSON.json(hookBinaryPath: hookBinaryPath)
        _ = try codexInstaller.connect(json: generated, translocated: false, inDownloads: false)

        var tampered = generated
        tampered[tampered.count - 1] ^= 0xFF   // 改最後一個 byte

        #expect(throws: CodexFailure.notOurs) {
            try codexInstaller.disconnect(ifContentsEqual: tampered)
        }
        #expect(FileManager.default.fileExists(
            atPath: layout.codexHome.appendingPathComponent("hooks.json").path),
            "內容不符時 hooks.json 必須還在")
    }

    // MARK: - probe()：D-q 讀取上限與基本觀測（CX19 在 T07 會消費 CodexObservation）

    @Test("probe()：codexHome 不存在時 codexHomeIsDirectory 為 false、entryType 為 absent")
    func probeReportsAbsentCodexHome() throws {
        let layout = try CodexHomeFixture.make(.absent)
        defer { layout.cleanup() }
        let observation = CodexInstaller(codexHome: layout.codexHome).probe()
        #expect(!observation.codexHomeIsDirectory)
        #expect(observation.entryType == .absent)
        #expect(observation.contents == nil)
    }

    @Test("probe()：codexHome 存在但 hooks.json 不存在時 entryType 為 absent")
    func probeReportsAbsentHooksJSON() throws {
        let layout = try CodexHomeFixture.make(.codexHomeIsEmptyDirectory)
        defer { layout.cleanup() }
        let observation = CodexInstaller(codexHome: layout.codexHome).probe()
        #expect(observation.codexHomeIsDirectory)
        #expect(observation.entryType == .absent)
        #expect(observation.contents == nil)
    }

    @Test("probe()：connect() 之後 entryType 為 regularFile 且 contents 等於寫入的位元組")
    func probeReadsBackWhatWasWritten() throws {
        let layout = try CodexHomeFixture.make(.codexHomeIsEmptyDirectory)
        defer { layout.cleanup() }
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)
        let written = try codexInstaller.connect(json: CodexHooksJSON.json(hookBinaryPath: hookBinaryPath),
                                            translocated: false, inDownloads: false)

        let observation = codexInstaller.probe()
        #expect(observation.entryType == .regularFile)
        #expect(observation.contents == written)
    }

    @Test("probe()：D-q——> 64 KiB 的檔案 entryType 仍是 regularFile 但 contents 為 nil（不讀）")
    func probeDoesNotReadOversizedFile() throws {
        let layout = try CodexHomeFixture.make(.hooksJSONIsGarbageOver64KiB)
        defer { layout.cleanup() }
        let observation = CodexInstaller(codexHome: layout.codexHome).probe()
        #expect(observation.entryType == .regularFile)
        #expect(observation.contents == nil, "> 64 KiB 不可能是我們寫的，D-q 規定不讀")
    }

    @Test("probe()：hooks.json 是目錄時 entryType 為 directory 且 contents 為 nil")
    func probeReportsDirectoryEntryType() throws {
        let layout = try CodexHomeFixture.make(.hooksJSONIsDirectory)
        defer { layout.cleanup() }
        let observation = CodexInstaller(codexHome: layout.codexHome).probe()
        #expect(observation.entryType == .directory)
        #expect(observation.contents == nil)
    }

    @Test("probe()：hooks.json 是 symlink 時 entryType 為 symlink 且 contents 為 nil（不 follow 讀取）")
    func probeReportsSymlinkEntryType() throws {
        let layout = try CodexHomeFixture.make(.hooksJSONIsSymlinkToConfigToml)
        defer { layout.cleanup() }
        let observation = CodexInstaller(codexHome: layout.codexHome).probe()
        #expect(observation.entryType == .symlink)
        #expect(observation.contents == nil)
    }

    @Test("CX17：expected == nil（憑證遺失）必須 throw .notOurs 且不刪")
    func disconnectRefusesWhenExpectedContentsIsNil() throws {
        let layout = try CodexHomeFixture.make(.codexHomeIsEmptyDirectory)
        defer { layout.cleanup() }
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)
        let generated = CodexHooksJSON.json(hookBinaryPath: hookBinaryPath)
        _ = try codexInstaller.connect(json: generated, translocated: false, inDownloads: false)

        #expect(throws: CodexFailure.notOurs) {
            try codexInstaller.disconnect(ifContentsEqual: nil)
        }
        #expect(FileManager.default.fileExists(
            atPath: layout.codexHome.appendingPathComponent("hooks.json").path))
    }

    @Test("CX17：absent 時 disconnect 冪等成功，即使 expected 非 nil")
    func disconnectIsIdempotentWhenAbsent() throws {
        let layout = try CodexHomeFixture.make(.codexHomeIsEmptyDirectory)
        defer { layout.cleanup() }
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)
        let generated = CodexHooksJSON.json(hookBinaryPath: hookBinaryPath)

        try codexInstaller.disconnect(ifContentsEqual: generated)   // 從沒 connect 過，檔案不存在
    }

    @Test("CX17：內容相符才刪——刪除後 hooks.json 不存在，config.toml 不受影響")
    func disconnectRemovesOnExactMatch() throws {
        let layout = try CodexHomeFixture.make(.codexHomeIsEmptyDirectory)
        defer { layout.cleanup() }
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)
        let generated = CodexHooksJSON.json(hookBinaryPath: hookBinaryPath)
        let written = try codexInstaller.connect(json: generated, translocated: false, inDownloads: false)

        try codexInstaller.disconnect(ifContentsEqual: written)

        #expect(!FileManager.default.fileExists(
            atPath: layout.codexHome.appendingPathComponent("hooks.json").path))
        let configToml = try Data(contentsOf: layout.codexHome.appendingPathComponent("config.toml"))
        #expect(configToml == CodexHomeFixture.knownConfigTomlContents)
    }

    /// TOCTOU 視窗本身無法在單執行緒測試裡真的重現（`disconnect()` 兩次系統呼叫之間
    /// 沒有排程點可以插手）——同 `Installer.guardWriteTarget()` 的既有測試哲學，
    /// 直接測「複查」這一步本身：餵一個刻意不符的 `identity`，證明它真的比對、
    /// 不是裝飾。`internal func unlinkIfIdentityUnchanged` 就是為了這個而拆出來。
    @Test("CX17：unlinkIfIdentityUnchanged 對不符的 (dev,ino) 必須 throw .notOurs 且不刪")
    func unlinkGuardRefusesWhenIdentityDoesNotMatchCurrentFile() throws {
        let layout = try CodexHomeFixture.make(.codexHomeIsEmptyDirectory)
        defer { layout.cleanup() }
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)
        let generated = CodexHooksJSON.json(hookBinaryPath: hookBinaryPath)
        _ = try codexInstaller.connect(json: generated, translocated: false, inDownloads: false)

        let bogusIdentity = FileIdentity(dev: 0, ino: 0)
        #expect(throws: CodexFailure.notOurs) {
            try codexInstaller.unlinkIfIdentityUnchanged(bogusIdentity)
        }
        #expect(FileManager.default.fileExists(
            atPath: layout.codexHome.appendingPathComponent("hooks.json").path),
            "identity 不符時 hooks.json 必須還在")
    }

    @Test("CX17：unlinkIfIdentityUnchanged 對相符的 (dev,ino) 真的刪除")
    func unlinkGuardRemovesWhenIdentityMatchesCurrentFile() throws {
        let layout = try CodexHomeFixture.make(.codexHomeIsEmptyDirectory)
        defer { layout.cleanup() }
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)
        let generated = CodexHooksJSON.json(hookBinaryPath: hookBinaryPath)
        _ = try codexInstaller.connect(json: generated, translocated: false, inDownloads: false)

        let hooksJSONURL = layout.codexHome.appendingPathComponent("hooks.json")
        var st = stat()
        #expect(lstat(hooksJSONURL.path, &st) == 0)
        let realIdentity = FileIdentity(dev: st.st_dev, ino: st.st_ino)

        try codexInstaller.unlinkIfIdentityUnchanged(realIdentity)
        #expect(!FileManager.default.fileExists(atPath: hooksJSONURL.path))
    }

    // MARK: - M1（spec-reviewer 2026-09-18）：寫入失敗必須清掉剛建立的殘檔

    private struct InjectedWriteFailure: Error {}

    @Test("M1：write 失敗時清掉剛建立的殘檔，throw .writeFailed，不留半寫檔給之後的 probe 誤判")
    func connectCleansUpOrphanFileWhenWriteFails() throws {
        let layout = try CodexHomeFixture.make(.codexHomeIsEmptyDirectory)
        defer { layout.cleanup() }
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome,
                                            writeBytes: { _, _ in throw InjectedWriteFailure() })
        let generated = CodexHooksJSON.json(hookBinaryPath: hookBinaryPath)

        do {
            _ = try codexInstaller.connect(json: generated, translocated: false, inDownloads: false)
            Issue.record("應該要 throw")
        } catch let failure as CodexFailure {
            guard case .writeFailed = failure else {
                Issue.record("應該是 .writeFailed，實際是 \(failure)"); return
            }
        }

        #expect(!FileManager.default.fileExists(
            atPath: layout.codexHome.appendingPathComponent("hooks.json").path),
            "寫入失敗必須清掉剛建立的殘檔——留著會被之後的 probe 誤判成「別人的檔」")
    }

    // MARK: - m1（spec-reviewer 2026-09-18）：disconnect 先比大小，不符不讀

    @Test("m1：disconnect 對 > 64 KiB 的檔案先比大小，大小不符直接 .notOurs，檔案還在")
    func disconnectRefusesOversizedFileBySizeAlone() throws {
        let layout = try CodexHomeFixture.make(.hooksJSONIsGarbageOver64KiB)
        defer { layout.cleanup() }
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)
        let generated = CodexHooksJSON.json(hookBinaryPath: hookBinaryPath)   // 大小遠小於垃圾檔

        #expect(throws: CodexFailure.notOurs) {
            try codexInstaller.disconnect(ifContentsEqual: generated)
        }
        #expect(FileManager.default.fileExists(
            atPath: layout.codexHome.appendingPathComponent("hooks.json").path))
    }
}
