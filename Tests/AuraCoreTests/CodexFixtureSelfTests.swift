import Testing
import Foundation

/// codex-support T01 自我測試：驗證新 fixture 真的有它們宣稱的性質——用真的
/// `lstat`／檔案內容，不是猜。**這些合理地是 GREEN**：驗的是 fixture 自己
/// （純 Foundation／POSIX），不是還沒寫的 `CodexInstaller`／`CodexHookPathCheck`
/// （T04／T06）。若這裡壞了，後面所有引用它們的 gate 都會在錯誤的地基上蓋房子。
///
/// `FakeCodexInstaller`／`FakeCodexStore` 的自我測試在 `Tests/AgentAuraAppTests/
/// CodexDoubleSelfTests.swift`——它們只被 App 層的 CX24／CX35／CX39／CX42 消費
/// （spec §8.1 file layout：兩個 fake 都列在 `AgentAuraAppTests` 底下，不是這裡），
/// 而 `AgentAuraAppTests`／`AuraCoreTests` 是兩個獨立的 SwiftPM test target，
/// 彼此看不到對方 `Support/` 底下的型別。
@Suite("Codex fixture 自我驗證")
struct CodexFixtureSelfTests {

    // ---- CodexHomeFixture ----

    @Test("八種形狀＋外部 symlink：每種都能建出來，且 lstat 型別符合宣稱")
    func everyShapeBuildsAndMatchesLstatKind() throws {
        for shape in CodexHomeFixture.Shape.allCases {
            let layout = try CodexHomeFixture.make(shape)
            defer { layout.cleanup() }
            var st = stat()
            let codexHomeExists = lstat(layout.codexHome.path, &st) == 0

            switch shape {
            case .absent:
                #expect(!codexHomeExists, "\(shape)：codexHome 不該存在")
            case .codexHomeIsRegularFile:
                #expect(codexHomeExists && (st.st_mode & S_IFMT) == S_IFREG,
                        "\(shape)：codexHome 應是普通檔")
            case .codexHomeIsExternalSymlink:
                #expect(codexHomeExists && (st.st_mode & S_IFMT) == S_IFLNK,
                        "\(shape)：codexHome 應是 symlink")
                let target = try #require(layout.externalCodexHomeTarget, "\(shape) 應有 externalCodexHomeTarget")
                #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("config.toml").path))
            // 以下六種都是「codexHome 本身是真目錄」——**逐一列出，不用 default:**
            // （T01b review m3／D-r 的禁令：`default` 是看起來很無害的防禦性寫法，
            // 卻能讓整條推導鏈靜默失效；`Shape` 未來新增 case 時，這裡必須跟著紅）。
            case .codexHomeIsEmptyDirectory, .hooksJSONIsRegularFile, .hooksJSONIsDirectory,
                 .hooksJSONIsSymlinkToConfigToml, .hooksJSONIsDanglingSymlink, .hooksJSONIsGarbageOver64KiB:
                #expect(codexHomeExists && (st.st_mode & S_IFMT) == S_IFDIR,
                        "\(shape)：codexHome 應是目錄")
            }
        }
    }

    @Test("有目錄的形狀都植入了內容已知的 config.toml，位元組與宣稱的常數相符")
    func everyDirectoryShapeSeedsKnownConfigToml() throws {
        let shapesWithDirectory: [CodexHomeFixture.Shape] = [
            .codexHomeIsEmptyDirectory, .hooksJSONIsRegularFile, .hooksJSONIsDirectory,
            .hooksJSONIsSymlinkToConfigToml, .hooksJSONIsDanglingSymlink, .hooksJSONIsGarbageOver64KiB,
        ]
        for shape in shapesWithDirectory {
            let layout = try CodexHomeFixture.make(shape)
            defer { layout.cleanup() }
            let onDisk = try Data(contentsOf: layout.codexHome.appendingPathComponent("config.toml"))
            #expect(onDisk == CodexHomeFixture.knownConfigTomlContents,
                    "\(shape)：config.toml 的內容應與 knownConfigTomlContents 逐位元組相符")
        }
    }

    @Test("hooksJSONIsSymlinkToConfigToml：hooks.json 真的是 symlink 且指向 config.toml")
    func hooksJSONSymlinkShapePointsAtConfigToml() throws {
        let layout = try CodexHomeFixture.make(.hooksJSONIsSymlinkToConfigToml)
        defer { layout.cleanup() }
        let hooksPath = layout.codexHome.appendingPathComponent("hooks.json").path
        var st = stat()
        #expect(lstat(hooksPath, &st) == 0 && (st.st_mode & S_IFMT) == S_IFLNK)
        let target = try FileManager.default.destinationOfSymbolicLink(atPath: hooksPath)
        #expect(target == "config.toml" || target.hasSuffix("/config.toml"),
                "hooks.json 應指向同目錄的 config.toml，實際指向 \(target)")
    }

    @Test("hooksJSONIsGarbageOver64KiB：檔案大小真的超過 64 KiB（D-q）")
    func garbageShapeExceeds64KiB() throws {
        let layout = try CodexHomeFixture.make(.hooksJSONIsGarbageOver64KiB)
        defer { layout.cleanup() }
        let attrs = try FileManager.default.attributesOfItem(
            atPath: layout.codexHome.appendingPathComponent("hooks.json").path)
        let size = attrs[.size] as? Int ?? 0
        #expect(size > 64 * 1024, "垃圾檔應 > 64 KiB，實際 \(size) bytes")
    }

    @Test("hooksJSONIsDanglingSymlink：lstat 看得到 symlink，stat 穿透後找不到目標")
    func danglingSymlinkShapeIsReallyDangling() throws {
        let layout = try CodexHomeFixture.make(.hooksJSONIsDanglingSymlink)
        defer { layout.cleanup() }
        let hooksPath = layout.codexHome.appendingPathComponent("hooks.json").path
        var lst = stat()
        #expect(lstat(hooksPath, &lst) == 0 && (lst.st_mode & S_IFMT) == S_IFLNK)
        var st = stat()
        #expect(stat(hooksPath, &st) != 0, "穿透 symlink 的 stat 應該失敗（斷鏈）")
    }

    // ---- CodexTwoSidedFixture ----

    @Test("兩側交錯 fixture：claudeHome 與 codexHome 同時存在於同一個 root，且互不重疊")
    func twoSidedFixtureHasBothHomesUnderOneRoot() throws {
        let layout = try CodexTwoSidedFixture.make()
        defer { layout.cleanup() }
        #expect(layout.claudeHome.path.hasPrefix(layout.root.path))
        #expect(layout.codexHome.path.hasPrefix(layout.root.path))
        #expect(layout.claudeHome.path != layout.codexHome.path)
        #expect(FileManager.default.fileExists(atPath: layout.claudeHome.appendingPathComponent("settings.json").path))
        let toml = try Data(contentsOf: layout.codexHome.appendingPathComponent("config.toml"))
        #expect(toml == CodexHomeFixture.knownConfigTomlContents)
    }

    // ---- CodexAdversarialPayloads ----

    @Test("五個對抗式 payload 都是合法可解析的 JSON")
    func everyAdversarialPayloadIsValidJSON() throws {
        for (name, data) in CodexAdversarialPayloads.all {
            let obj = try JSONSerialization.jsonObject(with: data)
            #expect(obj is [String: Any], "\(name)：應解析成 JSON 物件")
        }
    }

    @Test("toolResponse200KBString：tool_response 欄位真的是 200,000 字元的字串")
    func toolResponsePayloadIsReally200KB() throws {
        let obj = try JSONSerialization.jsonObject(with: CodexAdversarialPayloads.toolResponse200KBString) as? [String: Any]
        let response = try #require(obj?["tool_response"] as? String)
        #expect(response.count == 200_000)
    }

    @Test("missingPermissionMode／missingModel：對應欄位真的缺席")
    func missingFieldPayloadsReallyMissThem() throws {
        let a = try JSONSerialization.jsonObject(with: CodexAdversarialPayloads.missingPermissionMode) as? [String: Any]
        #expect(a?["permission_mode"] == nil)
        let b = try JSONSerialization.jsonObject(with: CodexAdversarialPayloads.missingModel) as? [String: Any]
        #expect(b?["model"] == nil)
    }

    // ---- AgentArgvFixtures ----

    @Test("argv 七格表：每格的 argv 都不是空表達式以外的東西——表本身結構完整")
    func argvTableHasSevenDistinctCases() {
        #expect(AgentArgvFixtures.cases.count == 7)
        let expectedValues = Set(AgentArgvFixtures.cases.map(\.expectedRawValue))
        #expect(expectedValues == ["claude", "codex"], "期望值只能是 claude／codex 兩種")
    }

    // ---- CodexPathFixtures ----

    @Test("路徑 fixture：10 格（4 個固定＋6 個字元），每個字元格的路徑真的含那個字元")
    func pathFixtureCasesContainTheirOwnCharacter() throws {
        #expect(CodexPathFixtures.cases.count == 4 + CodexPathFixtures.unsupportedCharacterSamples.count)
        let translocated = CodexPathFixtures.cases.filter(\.translocated)
        #expect(translocated.count == 2, "translocated 的格數應為 2（單獨一格＋含空白那格）")
        let clean = try #require(CodexPathFixtures.cases.first { $0.name.contains("負對照") })
        #expect(clean.translocated == false && clean.inDownloads == false)
        for c in CodexPathFixtures.unsupportedCharacterSamples {
            let matching = try #require(CodexPathFixtures.cases.first { $0.name == "unsupportedCharacter(\(c))" })
            #expect(matching.hookBinaryPath.contains(c),
                    "字元 \(c) 的 case 應該在 hookBinaryPath 裡真的出現這個字元")
        }
    }

    @Test("路徑 fixture：expectedRejection 逐格與 translocated／inDownloads／字元對得上（T01b M1）")
    func pathFixtureExpectedRejectionsAreConsistent() throws {
        for c in CodexPathFixtures.cases {
            if c.translocated || c.inDownloads {
                #expect(c.expectedRejection == "mustMoveToApplications",
                        "\(c.name)：translocated／inDownloads 的格期望值應為 mustMoveToApplications")
            } else if c.name.contains("負對照") {
                #expect(c.expectedRejection == nil, "\(c.name)：負對照格期望值應為 nil")
            } else {
                let ch = try #require(CodexPathFixtures.unsupportedCharacterSamples.first { c.hookBinaryPath.contains($0) })
                #expect(c.expectedRejection == "unsupportedCharacter(\(ch))",
                        "\(c.name)：期望值應為 unsupportedCharacter(\(ch))，實際 \(c.expectedRejection ?? "nil")")
            }
        }
        // translocatedAndContainsSpace 是優先序的資料化表達：即使路徑含空白，期望值仍是
        // mustMoveToApplications，不是 unsupportedCharacter(" ")。
        let combo = try #require(CodexPathFixtures.cases.first { $0.name.contains("驗優先序") })
        #expect(combo.expectedRejection == "mustMoveToApplications")
    }

}
