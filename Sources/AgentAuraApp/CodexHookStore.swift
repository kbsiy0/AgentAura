import Foundation

/// spec §4.5（R-2）：Codex hook 憑證的持久化——**不算 hash**，直接把 `connect()` 寫出去的
/// 完整 JSON **文字**存進 `UserDefaults`，`disconnect()` 前逐位元組比對。
///
/// `@MainActor` ＋ 注入 `UserDefaults`（同 `HookVerificationStore` 的既有形狀，R1：`Sendable`
/// 的 `CodexInstaller` 不得碰 `UserDefaults`，憑證 I/O 全部留在 app 層）。
///
/// **round-trip 是獨立的失敗面**（CX31）：`connect()` 回 `Data`、`disconnect(ifContentsEqual:)`
/// 比對 `Data`，中間經過這裡的一個文字鍵。任何編碼不對等 → `disconnect` 永遠比不中 →
/// `.notOurs` → 永遠刪不掉自己寫的檔 → 完整移除留殘留（`verify-uninstall.sh` 第 7 項 FAIL）。
@MainActor
final class CodexHookStore {
    /// `AgentAuraCodexHookContents`（spec §3）——CX42 用它跟 Claude 側三個
    /// `AgentAuraHook*` 鍵區分「另一側」。
    static let key = "AgentAuraCodexHookContents"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// `disconnect(ifContentsEqual:)` 要比對的那個值——讀出來的**必須**與 `write(_:)`
    /// 寫進去的逐位元組相等（CX31）。存的是文字（`String(decoding:as: UTF8.self)`），
    /// 讀回時原樣轉回 `Data`，中間不做任何裁剪／正規化。
    var contents: Data? {
        guard let text = defaults.string(forKey: Self.key) else { return nil }
        return Data(text.utf8)
    }

    /// `connect()` 成功之後呼叫——存的是**寫出去的那份位元組**，不是重新算一次。
    func write(_ bytes: Data) {
        defaults.set(String(decoding: bytes, as: UTF8.self), forKey: Self.key)
    }

    /// `disconnect()` 成功之後呼叫。
    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
