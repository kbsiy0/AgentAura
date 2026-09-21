import Testing
import Foundation
import AuraCore

/// T07：`CodexState.from(...)` 判定表（spec §3，`CodexState+From.swift`）。
///
/// **CX19 `codexStateCoversEveryObservationShape`**：定義域由五個維度的乘積推導
/// （`codexHomeIsDirectory`／`CodexObservation.EntryType.allCases`／磁碟 vs recorded／
/// 磁碟 vs currentExpected／`pathRejection`），不寫死格數——`entryType` 迴圈用
/// `.allCases`、`.blockedByBundlePath` 那格用 `RejectionKind.allCases.flatMap(Rejection.samples)`。
///
/// **CX34 `codexStalePathIsDetectedAndOffersReconnect`**：磁碟 == 憑證 != 現在預期 →
/// `.connectedStalePath`，三份內容都用真的產生器輸出（`CodexHooksJSON.json(...)`）、兩個不同路徑。
@Suite("CodexState.from 判定表（CX19／CX34）")
struct CodexStateTests {
    /// 兩個不同路徑各自跑一次真的產生器——CX34 要求「三份內容都用真產生器輸出」，不是
    /// 隨手湊的 `Data("A".utf8)`：這樣才驗到「兩份*合法產生器輸出*但路徑不同」這個真實情境
    /// （app 搬家），不是「兩個任意不同的位元組序列」這種弱化版本。
    static let contentsAtOldPath = CodexHooksJSON.json(hookBinaryPath: "/Applications/AgentAura.app/Contents/Resources/bin/aura-hook")
    static let contentsAtNewPath = CodexHooksJSON.json(hookBinaryPath: "/Applications/AgentAura-2.app/Contents/Resources/bin/aura-hook")
    static let unrelatedContents = Data("這是別人的合法 JSON，不是我們寫的".utf8)
    static let sampleRejection = CodexHookPathCheck.Rejection.mustMoveToApplications

    static func observation(codexHomeIsDirectory: Bool, entryType: CodexObservation.EntryType,
                            contents: Data?) -> CodexObservation {
        CodexObservation(codexHomeIsDirectory: codexHomeIsDirectory, entryType: entryType,
                         contents: contents, displayPath: nil)
    }

    @Test("第 1 列：codexHomeIsDirectory == false → .unavailable，無論 entryType／pathRejection")
    func notDirectoryAlwaysUnavailable() {
        #expect(CodexObservation.EntryType.allCases.count >= 5, "定義域塌陷了嗎？entryType 種類異常少")
        for entryType in CodexObservation.EntryType.allCases {
            for pathRejection: CodexHookPathCheck.Rejection? in [nil, Self.sampleRejection] {
                let obs = Self.observation(codexHomeIsDirectory: false, entryType: entryType, contents: nil)
                let state = CodexState.from(obs, recordedContents: nil,
                                            currentExpectedContents: Self.contentsAtNewPath, pathRejection: pathRejection)
                #expect(state == .unavailable, """
                    codexHomeIsDirectory=false entryType=\(entryType) pathRejection=\(String(describing: pathRejection)) \
                    應恆為 .unavailable，實際 \(state)
                    """)
            }
        }
    }

    @Test("第 2 列：regularFile ＋ 磁碟==recorded==currentExpected → .connected")
    func regularFileMatchingBothIsConnected() {
        let obs = Self.observation(codexHomeIsDirectory: true, entryType: .regularFile, contents: Self.contentsAtOldPath)
        let state = CodexState.from(obs, recordedContents: Self.contentsAtOldPath,
                                    currentExpectedContents: Self.contentsAtOldPath, pathRejection: nil)
        #expect(state == .connected)
    }

    @Test("第 3 列（CX34）：regularFile ＋ 磁碟==recorded ＋ !=currentExpected → .connectedStalePath，pathRejection 不改變結果")
    func regularFileMatchingRecordedButNotCurrentIsStale() {
        #expect(Self.contentsAtOldPath != Self.contentsAtNewPath, """
            兩個真產生器輸出必須不同（不同路徑），否則這條測試量不到「路徑變了」——實際兩者相等
            """)
        for pathRejection: CodexHookPathCheck.Rejection? in [nil, Self.sampleRejection] {
            let obs = Self.observation(codexHomeIsDirectory: true, entryType: .regularFile, contents: Self.contentsAtOldPath)
            let state = CodexState.from(obs, recordedContents: Self.contentsAtOldPath,
                                        currentExpectedContents: Self.contentsAtNewPath, pathRejection: pathRejection)
            #expect(state == .connectedStalePath, """
                pathRejection=\(String(describing: pathRejection)) 不該改變結果（判定表這一列是「任意」），\
                實際 \(state)
                """)
        }
    }

    @Test("第 4 列：regularFile 但磁碟／recorded 任一 nil 或不等 → .occupiedByOther")
    func regularFileMismatchIsOccupied() {
        let cases: [(disk: Data?, recorded: Data?)] = [
            (nil, Self.contentsAtOldPath),
            (Self.contentsAtOldPath, nil),
            (Self.contentsAtOldPath, Self.unrelatedContents),
        ]
        for c in cases {
            let obs = Self.observation(codexHomeIsDirectory: true, entryType: .regularFile, contents: c.disk)
            let state = CodexState.from(obs, recordedContents: c.recorded,
                                        currentExpectedContents: Self.contentsAtOldPath, pathRejection: nil)
            #expect(state == .occupiedByOther, """
                disk=\(String(describing: c.disk)) recorded=\(String(describing: c.recorded)) 應為 .occupiedByOther，\
                實際 \(state)
                """)
        }
    }

    @Test("第 5 列：directory／symlink／otherFile → .occupiedByOther，無論 pathRejection")
    func nonRegularOccupyingTypesAreOccupied() {
        let occupyingTypes: [CodexObservation.EntryType] = [.directory, .symlink, .otherFile]
        for entryType in occupyingTypes {
            for pathRejection: CodexHookPathCheck.Rejection? in [nil, Self.sampleRejection] {
                let obs = Self.observation(codexHomeIsDirectory: true, entryType: entryType, contents: nil)
                let state = CodexState.from(obs, recordedContents: nil,
                                            currentExpectedContents: Self.contentsAtOldPath, pathRejection: pathRejection)
                #expect(state == .occupiedByOther, "entryType=\(entryType) 應為 .occupiedByOther，實際 \(state)")
            }
        }
    }

    @Test("第 6 列：absent ＋ pathRejection 非 nil → .blockedByBundlePath(r)，逐 RejectionKind 樣本")
    func absentWithRejectionIsBlocked() {
        let samples = CodexHookPathCheck.RejectionKind.allCases.flatMap(CodexHookPathCheck.Rejection.samples)
        #expect(!samples.isEmpty, "Rejection.samples 的定義域是空的——gate 不能空跑")
        for rejection in samples {
            let obs = Self.observation(codexHomeIsDirectory: true, entryType: .absent, contents: nil)
            let state = CodexState.from(obs, recordedContents: nil,
                                        currentExpectedContents: Self.contentsAtOldPath, pathRejection: rejection)
            #expect(state == .blockedByBundlePath(rejection), "rejection=\(rejection) 應對應同一個 .blockedByBundlePath，實際 \(state)")
        }
    }

    @Test("第 7 列：absent ＋ pathRejection nil → .notConnected")
    func absentWithoutRejectionIsNotConnected() {
        let obs = Self.observation(codexHomeIsDirectory: true, entryType: .absent, contents: nil)
        let state = CodexState.from(obs, recordedContents: nil,
                                    currentExpectedContents: Self.contentsAtOldPath, pathRejection: nil)
        #expect(state == .notConnected)
    }

    /// CX19 定義域推導本身的正向對照：`CodexStateKind.allCases.flatMap(CodexState.samples)`
    /// 必須恰好覆蓋六態（`.blockedByBundlePath` 展開成多個樣本，但 `kind` 仍只映射回一個）。
    @Test("CodexStateKind.allCases.flatMap(samples) 的 kind 集合恰為六態")
    func samplesKindsCoverAllSixStates() {
        let kinds = Set(CodexStateKind.allCases.flatMap(CodexState.samples).map(\.kind))
        #expect(kinds == Set(CodexStateKind.allCases), """
            samples 展開後的 kind 集合是 \(kinds)，應恰好等於 CodexStateKind.allCases \
            （\(Set(CodexStateKind.allCases))）
            """)
    }

    /// CX40（純函式半，R-10）：`CodexHooksJSON.withheldSnippet(hookBinaryPath:pathRejection:)`
    /// 只看 `pathRejection`，跟 `CodexState` 完全無關——這裡先窮盡三個代表性 `pathRejection`
    /// 值（`nil`／`.mustMoveToApplications`／`.unsupportedCharacter(" ")`）。**跨
    /// `CodexStateKind` 的那一半**在 `CodexWiringSmokeTests.codexSnippetIsWithheldWhenPathWillVanish`
    /// （App 層，透過 `CodexRuntime.codexState`／`.codexSnippet` 讀決策層真正算出來的值）——
    /// 這條純函式本身不吃 `CodexStateKind`，在這裡跨它是空轉，兩條測試互相點名見對方 doc comment。
    @Test("CX40（純函式半）：withheldSnippet 窮盡三個代表性 pathRejection")
    func withheldSnippetExhaustsRepresentativeRejections() {
        let path = "/Applications/AgentAura.app/Contents/Resources/plugin/bin/aura-hook"
        #expect(CodexHooksJSON.withheldSnippet(hookBinaryPath: path, pathRejection: nil) != nil,
                "pathRejection == nil 時應該給 snippet")
        #expect(CodexHooksJSON.withheldSnippet(hookBinaryPath: path, pathRejection: .mustMoveToApplications) == nil,
                "pathRejection == .mustMoveToApplications 時應該扣住 snippet（R-10）")
        #expect(CodexHooksJSON.withheldSnippet(hookBinaryPath: path, pathRejection: .unsupportedCharacter(" ")) != nil,
                "pathRejection == .unsupportedCharacter 時仍應該給 snippet——那個路徑不會過期")
    }
}
