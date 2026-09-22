import Testing
import Foundation
import AuraCore
@testable import AuraHookFile

/// T06：`CodexInstaller` 只碰 `<codexHome>/hooks.json`——CX14／CX18（spec §4.4／§4.8／§6.3）。
///
/// **CX18 動手前先量的結果（T01 review 給 T06 的提醒，見計畫 T06 開頭）**：
/// `DirectoryTreeSnapshot.take(root:)` 內部呼叫 `FileManager.default.enumerator(at:)`。
/// 實測（`/tmp` 一次性 Swift 腳本，非 repo 內；用 `URL(fileURLWithPath:)`／
/// `isDirectory: true` 提示／`resolvingSymlinksInPath()` 各試一輪）：若把 root 直接
/// 設成**一個本身是 symlink 的 URL**，`enumerator(at:)` 既**不會穿透**去列舉目標內容、
/// 也**不會回報任何錯誤**——它單純回傳一個空的走訪序列（`count == 0`），因為
/// `enumerator(at:)` 判斷「這是不是可以走訪的目錄」時看的是 `URLResourceValues`
/// 對**字面路徑**（不 follow 最後一段 symlink）的 `isDirectoryKey`，對一個 symlink
/// 恆回 `false`。**這與計畫文字「會穿透」相反，但兩者導致的風險是同一種**：若直接寫
/// `take(root: layout.codexHome)`（`codexHome` 本身是 symlink）當「字面樹」，得到的
/// 恆是空字典，前後相減恆為空集合——斷言看起來過了，其實什麼都沒量到（套套邏輯）。
///
/// 另一方面，若 root 是**一般目錄**、其中某個**子項**才是指向目錄的 symlink，
/// `enumerator(at:)` 會把那個子項列成一個不透明的 entry（symlink 型別＋目標字串），
/// **不會**遞迴進去——這正是既有 `ClaudeHomeTreeSnapshot`／`take(root:alsoResolving:)`
/// 已經利用的行為，不需要在 `DirectoryTreeSnapshot` 上再加任何新方法：CX18 只要對
/// **`codexHome` 的上一層**（`CodexHomeFixture.Layout.root`，`codexHome` 在那裡只是
/// 一個字面子項）取快照，就能看到「`codexHome` 這個 symlink 本身沒變」；「realpath 樹」
/// 則直接對 fixture 已經提供的 `externalCodexHomeTarget`（也就是 `realpath(codexHome)`
/// 的目的地）取快照——兩者都是對**一般目錄**呼叫 `take(root:)`，不會踩到上面那個空字典陷阱。
@Suite("CodexInstaller 只碰 hooks.json（CX14／CX18）")
struct CodexPathScopeTests {

    private let hookBinaryPath = "/Applications/AgentAura.app/Contents/MacOS/aura-hook"

    // MARK: - CX14 codexInstallerTouchesOnlyHooksJSON

    @Test("CX14：connect() 後 codexHome 整棵樹差異恰為 {hooks.json}，config.toml 位元組不變")
    func codexInstallerTouchesOnlyHooksJSON() throws {
        let layout = try CodexHomeFixture.make(.codexHomeIsEmptyDirectory)
        defer { layout.cleanup() }
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)
        let before = DirectoryTreeSnapshot.take(root: layout.codexHome)

        _ = try codexInstaller.connect(json: CodexHooksJSON.json(hookBinaryPath: hookBinaryPath),
                                  translocated: false, inDownloads: false)

        let after = DirectoryTreeSnapshot.take(root: layout.codexHome)
        let delta = DirectoryTreeSnapshot.changedPaths(before: before, after: after)
        #expect(delta == ["hooks.json"], "connect() 後差異應恰為 {hooks.json}，實際：\(delta.sorted())")
        #expect(before["config.toml"] == after["config.toml"], "config.toml 的位元組必須完全不變")
    }

    @Test("CX14：已經接上時再 connect() 一次（EEXIST），差異為空集合")
    func codexInstallerSecondConnectTouchesNothing() throws {
        let layout = try CodexHomeFixture.make(.codexHomeIsEmptyDirectory)
        defer { layout.cleanup() }
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)
        _ = try codexInstaller.connect(json: CodexHooksJSON.json(hookBinaryPath: hookBinaryPath),
                                  translocated: false, inDownloads: false)
        let before = DirectoryTreeSnapshot.take(root: layout.codexHome)

        #expect(throws: CodexFailure.alreadyExists) {
            try codexInstaller.connect(json: CodexHooksJSON.json(hookBinaryPath: hookBinaryPath),
                                  translocated: false, inDownloads: false)
        }
        let after = DirectoryTreeSnapshot.take(root: layout.codexHome)
        #expect(DirectoryTreeSnapshot.changedPaths(before: before, after: after).isEmpty)
    }

    // MARK: - CX18 codexHomeSymlinkWritesInsideResolvedPath

    @Test("CX18：~/.codex 自己是外指 symlink 時，字面樹不變、realpath 樹差異恰為 {hooks.json}")
    func codexHomeSymlinkWritesInsideResolvedPath() throws {
        let layout = try CodexHomeFixture.make(.codexHomeIsExternalSymlink)
        defer { layout.cleanup() }
        guard let target = layout.externalCodexHomeTarget else {
            Issue.record(".codexHomeIsExternalSymlink 這個形狀必須提供 externalCodexHomeTarget")
            return
        }
        let codexInstaller = CodexInstaller(codexHome: layout.codexHome)

        let literalBefore = DirectoryTreeSnapshot.take(root: layout.root)
        let realBefore = DirectoryTreeSnapshot.take(root: target)

        _ = try codexInstaller.connect(json: CodexHooksJSON.json(hookBinaryPath: hookBinaryPath),
                                  translocated: false, inDownloads: false)

        let literalAfter = DirectoryTreeSnapshot.take(root: layout.root)
        let realAfter = DirectoryTreeSnapshot.take(root: target)

        // 「字面樹不變」：codexHome 這個 symlink 本身（型別／目標字串）完全不變；
        // root 底下其餘不是 external-codex-home 的東西也不該動——external-codex-home
        // 是 realpath 目的地本身在字面上也是 root 的一個子項，它會變是預期內的，
        // 用前綴排除它才是「字面樹不變」真正想講的事。
        #expect(literalBefore["codexHome"] == literalAfter["codexHome"],
                "codexHome 這個 symlink 本身（型別／目標）必須完全不變")
        let literalDelta = DirectoryTreeSnapshot.changedPaths(before: literalBefore, after: literalAfter)
        let unexpected = literalDelta.filter { !$0.hasPrefix("external-codex-home") }
        #expect(unexpected.isEmpty, "root 底下除了 external-codex-home 之外不該有任何變動：\(unexpected.sorted())")

        let realDelta = DirectoryTreeSnapshot.changedPaths(before: realBefore, after: realAfter)
        #expect(realDelta == ["hooks.json"], "realpath 樹的差異應恰為 {hooks.json}，實際：\(realDelta.sorted())")
    }

    /// 對照組（防止上面那條變成套套邏輯的自我檢查）：直接把 symlink 本身當 root
    /// 傳給 `take(root:)`，鎖住量到的「恆空字典」這個事實——如果 Foundation 未來
    /// 版本改變這個行為，這條會先紅，提醒回去重新檢查 CX18 用的座標系是否還成立。
    @Test("CX18 自我檢查：take(root:) 對『本身是 symlink』的 root 恆回傳空字典")
    func directoryTreeSnapshotOnSymlinkRootIsAlwaysEmpty() throws {
        let layout = try CodexHomeFixture.make(.codexHomeIsExternalSymlink)
        defer { layout.cleanup() }
        #expect(DirectoryTreeSnapshot.take(root: layout.codexHome).isEmpty, """
            量到的事實：enumerator(at:) 對『本身是 symlink』的 root 不穿透也不報錯，恆回傳空——\
            CX18 因此不能拿 take(root: codexHome) 當『字面樹』，必須用它的上一層 root
            """)
    }
}
