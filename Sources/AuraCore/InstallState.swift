import Foundation

/// spec `2026-09-10-app-shell-design.md` §3.1：`(st_dev, st_ino)`，
/// 判斷兩個**存在**的路徑是不是同一個一律用這個，不比字串（S1-A3：
/// 同一目錄 `resolvingSymlinksInPath` 給 `/var/…`、`realpath` 給 `/private/var/…`）。
public struct FileIdentity: Equatable, Sendable {
    public let dev: dev_t
    public let ino: ino_t
    public init(dev: dev_t, ino: ino_t) { self.dev = dev; self.ino = ino }
}

/// `Installer.probe()`（T03）的觀測結果。純資料，零判定邏輯——判定住在 `InstallState.from(_:verification:)`。
public struct LinkObservation: Equatable, Sendable {
    public let claudeHomeExists: Bool
    public let entryType: EntryType
    /// `realpath` 失敗的原因，`nil` = 成功。N3：斷鏈（errno=2）與自我迴圈（errno=62）
    /// 必須能分開判別，不能只看「identity 是不是 nil」——否則最常見的失敗顯示「掛載解不開」。
    public let resolveFailure: ResolveFailure?
    /// 僅在 `resolveFailure == nil` 時有意義。
    public let targetIsDirectory: Bool
    /// 解析後的目標。
    public let targetIdentity: FileIdentity?
    /// bundle 內 plugin 目錄的 identity；`swift test`／`swift run` 下恆為 `nil`。
    public let thisAppPluginIdentity: FileIdentity?
    public let hooksJSONExists: Bool
    public let hookBinaryExists: Bool
    /// `access(X_OK)`。**不足以證明能跑**（S0-A2：quarantine 下 exec 會被 SIGKILL）。
    public let hookBinaryExecutable: Bool
    /// 目標 `bin/aura-hook` 的身分戳：`"<dev>:<ino>:<mtime_sec>.<mtime_nsec>"`。
    public let hookBinaryStamp: String?
    /// R4：`readlink` 的原文（未解析）。`resolveFailure != nil` 時這是唯一還能判斷
    /// 「誰的掛載」的訊號（不違反 S1-A3——那條講的是判斷兩個**存在**的路徑是否同一個）。
    public let rawLinkTarget: String?
    /// 只給 UI 顯示，不參與判定。
    public let displayTargetPath: String?

    public init(
        claudeHomeExists: Bool, entryType: EntryType, resolveFailure: ResolveFailure?,
        targetIsDirectory: Bool, targetIdentity: FileIdentity?, thisAppPluginIdentity: FileIdentity?,
        hooksJSONExists: Bool, hookBinaryExists: Bool, hookBinaryExecutable: Bool,
        hookBinaryStamp: String?, rawLinkTarget: String?, displayTargetPath: String?
    ) {
        self.claudeHomeExists = claudeHomeExists
        self.entryType = entryType
        self.resolveFailure = resolveFailure
        self.targetIsDirectory = targetIsDirectory
        self.targetIdentity = targetIdentity
        self.thisAppPluginIdentity = thisAppPluginIdentity
        self.hooksJSONExists = hooksJSONExists
        self.hookBinaryExists = hookBinaryExists
        self.hookBinaryExecutable = hookBinaryExecutable
        self.hookBinaryStamp = hookBinaryStamp
        self.rawLinkTarget = rawLinkTarget
        self.displayTargetPath = displayTargetPath
    }

    public enum EntryType: String, Sendable, CaseIterable { case absent, symlink, directory, otherFile }
    public enum ResolveFailure: Equatable, Sendable { case notFound, loop, permissionDenied, other(Int32) }
}

/// R2：`.inFlight` = 背景驗證**確實正在跑**；`.unknown` = 沒人在跑也沒憑證——
/// 兩者的 chip 文案不同，「檢查中…」是關於進行中的宣稱，沒東西在進行時就是說謊。
/// **不是 `LinkObservation` 的欄位**，是 `InstallState.from(_:verification:)` 的第二個參數。
///
/// r6②：`.unconfirmed` = exec 驗證**無法確認**（有界等待逾時或 spawn 本身丟錯）——與
/// `.blocked`（真的跑過、**確實沒有產物**）不同。若把逾時也寫成 `blocked`，重開之後
/// chip 會**永久**顯示「macOS 擋住了 hook」，那是被持久化的誤指控（S2-11）。
public enum Verification: String, Sendable, CaseIterable { case verified, blocked, unconfirmed, inFlight, unknown }

/// R4：誰的掛載。三值而非 `Bool`——解析失敗時算不出 identity，`Bool` 只能猜，
/// 猜錯的後果是最常見的失敗（app 被搬走）走到需要使用者明確選擇的 `.replaceExternal`。
public enum MountOwner: String, Sendable, CaseIterable { case thisApp, external, unknown }

public enum InstallState: Equatable, Sendable {
    case claudeNotFound
    case notConnected
    /// `verified` = 曾經以 exec 驗證過**這一份**目標（identity+mtime 相符）。
    case connected(owner: MountOwner, verified: Verification)
    case broken(Reason, owner: MountOwner)

    /// **9 個**（r6②：新增 `hookUnconfirmed`；S2-1：11 是狀態總數，不是 Reason 數）。
    public enum Reason: String, Sendable, CaseIterable {
        case targetMissing        // realpath errno=ENOENT：目標不存在（app 被搬走／刪掉）
        case targetUnresolvable   // realpath 迴圈／權限／其他 errno
        case notAPlugin           // 解析成功但不是目錄，或沒有 hooks/hooks.json
        case hookMissing          // 沒有 bin/aura-hook
        case hookNotExecutable    // 在但沒有 x 位
        case hookBlockedOrBroken  // 真的跑過但沒有產物：quarantine SIGKILL／arch 不符／複製損壞
        case hookUnconfirmed      // 逾時／spawn 丟錯：無法確認，不得反過來誤指控 macOS（r6②／S2-11）
        case occupiedByDirectory  // 路徑是實體目錄（別人的安裝）
        case occupiedByFile       // 路徑是普通檔案 → 絕不移除
    }
}

extension InstallState {
    /// spec §3.1 判定順序（9 步），純函式、零 I/O、窮盡且不得有 `default`。
    /// 呼叫順序是強制的（T01 必辦④，一次 stat、一個所有者）：
    /// `Installer.probe()` → `store.verification(for:)` → `InstallState.from(obs, verification: v)`。
    public static func from(_ obs: LinkObservation, verification: Verification) -> InstallState {
        guard obs.claudeHomeExists else { return .claudeNotFound }

        switch obs.entryType {
        case .absent:
            return .notConnected
        case .otherFile:
            // 路徑上根本不是掛載，owner 沒有意義，一律 .unknown。
            return .broken(.occupiedByFile, owner: .unknown)
        case .directory:
            return .broken(.occupiedByDirectory, owner: .unknown)
        case .symlink:
            let owner = mountOwner(of: obs)

            if let failure = obs.resolveFailure {
                switch failure {
                case .notFound:
                    return .broken(.targetMissing, owner: owner)
                case .loop, .permissionDenied, .other:
                    return .broken(.targetUnresolvable, owner: owner)
                }
            }

            // resolveFailure == nil（解析成功）之後：
            // 「symlink → 普通檔案」與「是目錄但缺 hooks.json」刻意落同一個 .notAPlugin
            // （N3 追加，見 §6.3 G1 的註記，不准為了看起來該分開補第 9 個 Reason）。
            guard obs.targetIsDirectory else {
                return .broken(.notAPlugin, owner: owner)
            }
            guard obs.hooksJSONExists else {
                return .broken(.notAPlugin, owner: owner)
            }
            guard obs.hookBinaryExists else {
                return .broken(.hookMissing, owner: owner)
            }
            guard obs.hookBinaryExecutable else {
                return .broken(.hookNotExecutable, owner: owner)
            }
            if verification == .blocked {
                return .broken(.hookBlockedOrBroken, owner: owner)
            }
            if verification == .unconfirmed {
                return .broken(.hookUnconfirmed, owner: owner)
            }
            return .connected(owner: owner, verified: verification)
        }
    }

    /// §3.1 第 5 步：`targetIdentity` 可比對時用 `(dev, ino)`。
    ///
    /// **r6①**：`targetIdentity == nil`（解析失敗）時**不得只看「相不相符」**就判
    /// `.external`——app 被搬走時 `rawLinkTarget` 是舊路徑、`Bundle.main.resourceURL` 是
    /// 新路徑，兩者必不相符，照字面「不相符 → `.external`」會讓最常見的失敗又走回 R4
    /// 修掉的 `.replaceExternal`。改成依 `resolveFailure` 分流：
    /// - 正向命中（`rawLinkTarget` 以 `resourcePath` 為前綴）→ `.thisApp`；
    /// - 不相符 ＋ `.notFound`（**目標真的不存在，沒有東西會被毀**）→ `.unknown`
    ///   → affordance `.connect`；
    /// - 不相符 ＋ `.loop`／`.permissionDenied`／`.other`（**目標可能還在，只是解不開**）
    ///   → `.external` → affordance `.replaceExternal`，要使用者明確選擇（否則權限被拒的
    ///   活掛載會被靜默替換，S1-A7 家族）；
    /// - `rawLinkTarget == nil` 或 `resolveFailure == nil`（理論上不應在這個分支發生，
    ///   `targetIdentity == nil` 本應伴隨解析失敗；防禦性地回 `.unknown`）。
    private static func mountOwner(of obs: LinkObservation) -> MountOwner {
        if let targetIdentity = obs.targetIdentity {
            guard let thisApp = obs.thisAppPluginIdentity else { return .unknown }
            return targetIdentity == thisApp ? .thisApp : .external
        }
        if let rawLinkTarget = obs.rawLinkTarget,
           let resourcePath = Bundle.main.resourceURL?.path,
           rawLinkTarget.hasPrefix(resourcePath) {
            return .thisApp
        }
        guard let failure = obs.resolveFailure else { return .unknown }
        switch failure {
        case .notFound:
            return .unknown
        case .loop, .permissionDenied, .other:
            return .external
        }
    }
}
