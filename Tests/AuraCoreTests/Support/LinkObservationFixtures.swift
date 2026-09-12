import Foundation
import AuraCore

// `LinkObservation` fixture 全覆蓋（spec §6.1、§6.3 G1）。這些值本身是純資料，
// 沒有生產邏輯可測；`LinkObservationFixtureCoverageTests` 驗的是「fixture 集合
// 真的涵蓋每一個維度」；`InstallStateTests`（G1）拿去餵 `InstallState.from(_:verification:)`。

enum LinkObservationFixtures {
    static let thisApp = FileIdentity(dev: 1, ino: 100)
    static let externalMount = FileIdentity(dev: 1, ino: 200)

    private static func base(
        claudeHomeExists: Bool = true,
        entryType: LinkObservation.EntryType,
        resolveFailure: LinkObservation.ResolveFailure? = nil,
        targetIsDirectory: Bool = false,
        targetIdentity: FileIdentity? = nil,
        thisAppPluginIdentity: FileIdentity? = thisApp,
        hooksJSONExists: Bool = false,
        hookBinaryExists: Bool = false,
        hookBinaryExecutable: Bool = false,
        hookBinaryStamp: String? = nil,
        rawLinkTarget: String? = nil,
        displayTargetPath: String? = nil
    ) -> LinkObservation {
        LinkObservation(claudeHomeExists: claudeHomeExists, entryType: entryType,
                        resolveFailure: resolveFailure, targetIsDirectory: targetIsDirectory,
                        targetIdentity: targetIdentity, thisAppPluginIdentity: thisAppPluginIdentity,
                        hooksJSONExists: hooksJSONExists, hookBinaryExists: hookBinaryExists,
                        hookBinaryExecutable: hookBinaryExecutable, hookBinaryStamp: hookBinaryStamp,
                        rawLinkTarget: rawLinkTarget, displayTargetPath: displayTargetPath)
    }

    // MARK: - claudeHomeExists / entryType 四值

    static let claudeHomeMissing = base(claudeHomeExists: false, entryType: .absent)
    static let notConnected = base(entryType: .absent)
    static let occupiedByFile = base(entryType: .otherFile)
    static let occupiedByDirectory = base(entryType: .directory)

    // MARK: - symlink：resolveFailure（N3：斷鏈 ≠ 迴圈）

    static let brokenTargetMissing = base(entryType: .symlink, resolveFailure: .notFound,
                                          rawLinkTarget: "/Applications/Old.app/Contents/Resources/plugin")
    static let brokenLoop = base(entryType: .symlink, resolveFailure: .loop,
                                 rawLinkTarget: "/Users/x/.claude/skills/agentaura")
    static let brokenPermissionDenied = base(entryType: .symlink, resolveFailure: .permissionDenied,
                                             rawLinkTarget: "/private/restricted/plugin")
    static let brokenOtherErrno = base(entryType: .symlink, resolveFailure: .other(5),
                                       rawLinkTarget: "/dev/nonsense")

    // MARK: - symlink：解析成功，指向 thisApp／external

    static let symlinkToThisAppComplete = base(
        entryType: .symlink, targetIsDirectory: true, targetIdentity: thisApp,
        hooksJSONExists: true, hookBinaryExists: true, hookBinaryExecutable: true,
        hookBinaryStamp: "1:1000:1700000000.0", rawLinkTarget: "/Applications/AgentAura.app/Contents/Resources/plugin")

    static let symlinkToExternalComplete = base(
        entryType: .symlink, targetIsDirectory: true, targetIdentity: externalMount,
        hooksJSONExists: true, hookBinaryExists: true, hookBinaryExecutable: true,
        hookBinaryStamp: "1:2000:1700000000.0", rawLinkTarget: "/Users/x/Code/AgentAura/plugin")

    /// 解析成功但**目標不是目錄**（`realpath` 成功、指向一個普通檔案）——
    /// 與「是目錄但缺 hooks.json」刻意落同一個 `.notAPlugin`（N3 追加，見 G1 註記）。
    static let symlinkToRegularFile = base(
        entryType: .symlink, targetIsDirectory: false, targetIdentity: externalMount,
        rawLinkTarget: "/Users/x/somefile.txt")

    static let symlinkMissingHooksJSON = base(
        entryType: .symlink, targetIsDirectory: true, targetIdentity: externalMount,
        hooksJSONExists: false, rawLinkTarget: "/Users/x/Code/AgentAura/plugin")

    static let symlinkMissingHookBinary = base(
        entryType: .symlink, targetIsDirectory: true, targetIdentity: externalMount,
        hooksJSONExists: true, hookBinaryExists: false, rawLinkTarget: "/Users/x/Code/AgentAura/plugin")

    static let symlinkHookNotExecutable = base(
        entryType: .symlink, targetIsDirectory: true, targetIdentity: externalMount,
        hooksJSONExists: true, hookBinaryExists: true, hookBinaryExecutable: false,
        rawLinkTarget: "/Users/x/Code/AgentAura/plugin")

    /// 二進位存在且有 x 位，但 exec 會被 SIGKILL（S0-A2）——`LinkObservation` 本身看起來
    /// 完好（`hookBinaryExecutable == true`），差別只在後續的 `Verification`（不在這個欄位上）；
    /// 只有 exec 驗證（T03）抓得到，這裡先把「看起來完好」的那一半 fixture 準備好。
    static let symlinkHookExecutableButQuarantined = base(
        entryType: .symlink, targetIsDirectory: true, targetIdentity: externalMount,
        hooksJSONExists: true, hookBinaryExists: true, hookBinaryExecutable: true,
        hookBinaryStamp: "1:2000:1700000000.0", rawLinkTarget: "/Users/x/Downloads/AgentAura.app/Contents/Resources/plugin")

    // MARK: - thisAppPluginIdentity == nil（bundle 不完整／`swift run`／**`swift test` 就是這一格**）

    static let bundleIncompleteWithRawLinkTarget = base(
        entryType: .symlink, targetIsDirectory: true, targetIdentity: nil,
        thisAppPluginIdentity: nil, hooksJSONExists: true, hookBinaryExists: true, hookBinaryExecutable: true,
        rawLinkTarget: "/Users/x/Code/AgentAura/plugin")

    static let bundleIncompleteWithoutRawLinkTarget = base(
        entryType: .symlink, resolveFailure: .notFound, targetIdentity: nil,
        thisAppPluginIdentity: nil, rawLinkTarget: nil)

    // MARK: - 憑證：hookBinaryStamp 有／無（配合外部的 `Verification` 四值，交叉見下方 coverage）

    static let stampPresent = symlinkToThisAppComplete
    static let stampAbsent = base(entryType: .symlink, targetIsDirectory: true, targetIdentity: thisApp,
                                  hooksJSONExists: true, hookBinaryExists: true, hookBinaryExecutable: true,
                                  hookBinaryStamp: nil)

    static let all: [String: LinkObservation] = [
        "claudeHomeMissing": claudeHomeMissing, "notConnected": notConnected,
        "occupiedByFile": occupiedByFile, "occupiedByDirectory": occupiedByDirectory,
        "brokenTargetMissing": brokenTargetMissing, "brokenLoop": brokenLoop,
        "brokenPermissionDenied": brokenPermissionDenied, "brokenOtherErrno": brokenOtherErrno,
        "symlinkToThisAppComplete": symlinkToThisAppComplete, "symlinkToExternalComplete": symlinkToExternalComplete,
        "symlinkToRegularFile": symlinkToRegularFile, "symlinkMissingHooksJSON": symlinkMissingHooksJSON,
        "symlinkMissingHookBinary": symlinkMissingHookBinary, "symlinkHookNotExecutable": symlinkHookNotExecutable,
        "symlinkHookExecutableButQuarantined": symlinkHookExecutableButQuarantined,
        "bundleIncompleteWithRawLinkTarget": bundleIncompleteWithRawLinkTarget,
        "bundleIncompleteWithoutRawLinkTarget": bundleIncompleteWithoutRawLinkTarget,
        "stampAbsent": stampAbsent,
    ]
}
