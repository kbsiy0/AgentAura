import Testing
import Foundation
import AuraCore

/// T01 必辦：`LinkObservation` fixture 全覆蓋（spec §6.1）。
///
/// 這些測試驗的是「fixture 集合本身有沒有涵蓋每一個維度」——不是驗還沒寫的
/// `InstallState.from(_:verification:)`（那是 T02 的 `InstallStateTests`／G1）。
/// **這裡合理地是 GREEN**：跟 `AuraHookCLITests.fuzzedRealPayloadsAreSilent`
/// 的 `seenEvent == allEvents` 一樣，是「取樣／fixture 完整性」的自我檢查，
/// 不是對生產行為的斷言。
@Suite("LinkObservation fixture 覆蓋度")
struct LinkObservationFixtureCoverageTests {

    @Test("entryType 四值都有 fixture")
    func entryTypeCoversAllFour() {
        let covered = Set(LinkObservationFixtures.all.values.map(\.entryType))
        #expect(covered == Set(LinkObservation.EntryType.allCases), """
            entryType 缺：\(Set(LinkObservation.EntryType.allCases).subtracting(covered))
            """)
    }

    @Test("resolveFailure：斷鏈（errno=2）與自我迴圈（errno=62）必須是不同的 fixture（N3）")
    func resolveFailureSeparatesNotFoundFromLoop() {
        #expect(LinkObservationFixtures.brokenTargetMissing.resolveFailure == .notFound)
        #expect(LinkObservationFixtures.brokenLoop.resolveFailure == .loop)
        #expect(LinkObservationFixtures.brokenTargetMissing.resolveFailure
                != LinkObservationFixtures.brokenLoop.resolveFailure,
                "斷鏈與自我迴圈的 resolveFailure 必須可分辨，否則最常見的失敗會拿到說謊的文案")
        // permissionDenied／other 也要各自存在且與前兩者不同。
        let failures: Set<String> = [
            "\(LinkObservationFixtures.brokenTargetMissing.resolveFailure!)",
            "\(LinkObservationFixtures.brokenLoop.resolveFailure!)",
            "\(LinkObservationFixtures.brokenPermissionDenied.resolveFailure!)",
            "\(LinkObservationFixtures.brokenOtherErrno.resolveFailure!)",
        ]
        #expect(failures.count == 4, "四種 resolveFailure fixture 必須兩兩不同，實際只有 \(failures.count) 種文字表示")
    }

    @Test("targetIsDirectory：目錄與非目錄（symlink 指向普通檔案）都有 fixture")
    func targetIsDirectoryCoversBoth() {
        #expect(LinkObservationFixtures.symlinkToThisAppComplete.targetIsDirectory == true)
        #expect(LinkObservationFixtures.symlinkToRegularFile.targetIsDirectory == false)
        #expect(LinkObservationFixtures.symlinkToRegularFile.resolveFailure == nil,
                "指向普通檔案時 realpath 是成功的——這正是與『解不開』要分開的地方")
    }

    @Test("三個 hook 檔案旗標各自獨立可組合（hooksJSONExists／hookBinaryExists／hookBinaryExecutable）")
    func hookFileFlagsAreIndependentlyCovered() {
        #expect(LinkObservationFixtures.symlinkMissingHooksJSON.hooksJSONExists == false)
        #expect(LinkObservationFixtures.symlinkMissingHookBinary.hooksJSONExists == true)
        #expect(LinkObservationFixtures.symlinkMissingHookBinary.hookBinaryExists == false)
        #expect(LinkObservationFixtures.symlinkHookNotExecutable.hookBinaryExists == true)
        #expect(LinkObservationFixtures.symlinkHookNotExecutable.hookBinaryExecutable == false)
        #expect(LinkObservationFixtures.symlinkToThisAppComplete.hookBinaryExecutable == true)
    }

    @Test("hookBinaryStamp 有／無都有 fixture，且 exec 會被殺的那一格看起來完好（只有 exec 驗證抓得到）")
    func hookBinaryStampPresenceCovered() {
        #expect(LinkObservationFixtures.stampAbsent.hookBinaryStamp == nil)
        #expect(LinkObservationFixtures.symlinkToThisAppComplete.hookBinaryStamp != nil)
        let quarantined = LinkObservationFixtures.symlinkHookExecutableButQuarantined
        #expect(quarantined.hookBinaryExecutable == true, "看起來完好——access(X_OK) 不足以證明能跑（S0-A2）")
    }

    /// R4：`thisAppPluginIdentity == nil`（`swift test` 就是這一格）搭配 `rawLinkTarget` 有／無，
    /// 兩種組合都要能餵給之後 T02 的 owner 判定。
    @Test("thisAppPluginIdentity == nil 時，rawLinkTarget 有／無兩種都有 fixture")
    func bundleIncompleteCoversRawLinkTargetPresenceAndAbsence() {
        let withTarget = LinkObservationFixtures.bundleIncompleteWithRawLinkTarget
        let withoutTarget = LinkObservationFixtures.bundleIncompleteWithoutRawLinkTarget
        #expect(withTarget.thisAppPluginIdentity == nil)
        #expect(withTarget.rawLinkTarget != nil)
        #expect(withoutTarget.thisAppPluginIdentity == nil)
        #expect(withoutTarget.rawLinkTarget == nil)
    }

    @Test("Verification 五值（含 .inFlight／.unconfirmed）都可列舉，供之後與 hookBinaryStamp 交叉組合")
    func verificationHasFiveDistinctCases() {
        // r6②：新增 .unconfirmed（逾時／spawn 丟錯，與 .blocked「確實沒有產物」不同格）。
        #expect(Set(Verification.allCases).count == 5, "Verification 應恰好 5 個 case")
        #expect(Verification.allCases.contains(.inFlight), "inFlight 不得漏掉——它與 unknown 的文案必須分得開（R2）")
        #expect(Verification.allCases.contains(.unconfirmed),
                "unconfirmed 不得漏掉——它與 blocked 的文案必須分得開，否則逾時會被誤指控成 macOS 擋住（S2-11）")
    }

    @Test("MountOwner 三值都可列舉，供之後 owner 判定各自可達")
    func mountOwnerHasThreeDistinctCases() {
        #expect(Set(MountOwner.allCases) == [.thisApp, .external, .unknown])
    }

    /// fixture 集合不得意外重複計算（每個具名 fixture 對應一個獨立值），
    /// 避免「看起來涵蓋很多維度、其實是同一顆 fixture 掛了很多名字」。
    @Test("具名 fixture 彼此不完全相同（防止掛假名充數）")
    func namedFixturesAreNotAllIdentical() {
        let values = Array(LinkObservationFixtures.all.values)
        #expect(values.count >= 15, "fixture 數量應有規模，實際 \(values.count)")
        let distinct = Set(values.map { "\($0)" })
        #expect(distinct.count == values.count, "有 fixture 的字串表示完全相同——可能是複製貼上忘了改欄位")
    }
}
