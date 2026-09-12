import Foundation
import AuraCore

/// spec §3.1／§6.3：exec 驗證憑證的持久化與合流。**`@MainActor` ＋ 注入 `UserDefaults`**
/// （比照 `PaletteStore`）——`Sendable` 的 `Installer` 不得碰 `UserDefaults`（R1），
/// 憑證讀寫因此全部留在這裡。呼叫順序是強制的（T01 必辦④）：
/// `Installer.probe()` → `hookBinaryStamp` → `store.verification(for:)` → `InstallState.from(_:verification:)`。
@MainActor
protocol HookVerificationStoring: AnyObject {
    func verification(for stamp: String?) -> Verification
}

@MainActor
final class HookVerificationStore: HookVerificationStoring {
    /// 三個互斥鍵（r6②）：值都是 `"<dev>:<ino>:<mtime_sec>.<mtime_nsec>"`（`Installer` 算，
    /// 用 `st_mtimespec`——同一秒內重建的 hook 不會讓憑證失效，S2-9）。
    static let verifiedKey = "AgentAuraHookVerified"
    static let blockedKey = "AgentAuraHookBlocked"
    static let unconfirmedKey = "AgentAuraHookUnconfirmed"

    private let defaults: UserDefaults
    /// T01 必辦⑤／R2：合流 guard——已經有一個在跑就不開第二個（啟動驗證／`recheckHook`／
    /// `.blocked` 重驗共用，T08 接線）。因為本類別是 `@MainActor`，「檢查與設定」天然原子、
    /// 不需要額外的鎖。`inFlight != nil` **正好就是** `.inFlight` 的訊號——序列化與
    /// 「檢查中…」文案的誠實性是同一個機制，不是兩件事。
    private(set) var inFlight: Task<Void, Never>?

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// `inFlight` 優先於任何鍵比對——即使 stamp 精準吻合已驗證的鍵，還在跑時也不能搶答
    /// 「已接上」。`stamp == nil`（沒有目標可驗）一律 `.unknown`。
    func verification(for stamp: String?) -> Verification {
        if inFlight != nil { return .inFlight }
        guard let stamp else { return .unknown }
        if defaults.string(forKey: Self.verifiedKey) == stamp { return .verified }
        if defaults.string(forKey: Self.blockedKey) == stamp { return .blocked }
        if defaults.string(forKey: Self.unconfirmedKey) == stamp { return .unconfirmed }
        return .unknown
    }

    func writeVerified(_ stamp: String) { write(stamp, to: Self.verifiedKey) }
    func writeBlocked(_ stamp: String) { write(stamp, to: Self.blockedKey) }
    func writeUnconfirmed(_ stamp: String) { write(stamp, to: Self.unconfirmedKey) }

    /// E8（/simplify 波次2，alt#4／reuse#6）：「exec 驗證結果 → 該寫哪個憑證鍵 → 該產出
    /// 哪個 `Verification`」單一寫入點——原本 `beginBackgroundVerification` 養了一個
    /// 平行子集 enum（`VerifyOutcome`）＋三路 switch 才走到同樣三個 `write*`，
    /// 新增第四種結果要同時改兩個地方，型別系統只逼你改其中一個。回傳值正好就是
    /// 呼叫端要 `apply(obs:verification:)` 的那個 `Verification`。
    func record(_ result: Result<String, Error>, fallbackStamp: String) -> Verification {
        switch result {
        case .success(let stamp):
            writeVerified(stamp)
            return .verified
        case .failure(let error):
            switch error {
            case InstallerFailure.hookBlockedOrBroken(let stamp):
                writeBlocked(stamp)
                return .blocked
            case InstallerFailure.hookUnconfirmed(let stamp):
                writeUnconfirmed(stamp)
                return .unconfirmed
            default:
                // R2：unknown 不得為終態——任何未預期的失敗也必須寫回一個非 unknown 的值。
                // `default:` 在這裡合法（同原本的 `catch { }` 兜底）：switch 的對象是
                // 開放的 `Error`，不是窮盡的 `InstallerFailure`。
                writeUnconfirmed(fallbackStamp)
                return .unconfirmed
            }
        }
    }

    /// 三鍵互斥：寫一個要清掉另兩個。
    private func write(_ stamp: String, to key: String) {
        for other in [Self.verifiedKey, Self.blockedKey, Self.unconfirmedKey] where other != key {
            defaults.removeObject(forKey: other)
        }
        defaults.set(stamp, forKey: key)
    }

    /// 啟動一段背景驗證；已經有一個在跑就跳過（回 `false`）。跑完自動清掉 `inFlight`。
    @discardableResult
    func beginVerification(_ work: @escaping () async -> Void) -> Bool {
        guard inFlight == nil else { return false }
        inFlight = Task { [weak self] in
            await work()
            self?.inFlight = nil
        }
        return true
    }
}
