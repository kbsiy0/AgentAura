import Foundation

/// E12（/simplify 波次2，reuse#11）：布林偏好的 `UserDefaults` 搬運層——比照既有的
/// `PaletteStore`／`HookVerificationStore`（「搬運層是一個注入 `defaults` 的小型別」）。
///
/// 兩個既有偏好（`userReduceMotion`／`iconPlate`）原本各寫一套 load/persist，且兩種讀法：
/// `defaults.bool(forKey:)`（缺鍵讀成 `false`，適合預設 `false` 的偏好）與
/// `defaults.object(forKey:) as? Bool ?? true`（適合預設 `true` 的偏好，`loadIconPlate`
/// 原本的 doc comment 記過「用錯那種讀法會把『從未設定過』誤讀成『使用者關掉』」這個坑）。
/// 第三個偏好要加時，作者得在兩種寫法裡任選一種——這裡把「該用哪種讀法」收進型別本身，
/// 讓正確性不再取決於複製哪一份程式碼。
struct BoolPreference {
    let key: String
    let defaultValue: Bool

    /// 一律用 `object(forKey:)` 而非 `bool(forKey:)`——`object(forKey:)` 對缺鍵回 `nil`，
    /// 能與「使用者明確設成 false」分開；`bool(forKey:)` 對缺鍵恆回 `false`，
    /// 對預設 `true` 的偏好會誤把「從未設定過」讀成「使用者關掉」。
    func load(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }

    func persist(_ value: Bool, to defaults: UserDefaults) {
        defaults.set(value, forKey: key)
    }
}
