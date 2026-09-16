import Foundation

/// 字串 rawValue 的 enum 偏好在 `UserDefaults` 裡的搬運層——比照既有的 `BoolPreference`
/// （「搬運層是一個注入 `defaults` 的小型別」）。
///
/// `/simplify`（icon-shapes 波次，reuse#4）：`LanguagePreference` 與 `IconShapePreference`
/// 原本各寫一份完全同形的 `load`／`persist`。`BoolPreference` 的 doc comment 當初就寫過
/// 同一個理由——「第三個偏好要加時，作者得在兩種寫法裡任選一種，所以把該用哪種讀法收進
/// 型別本身」——而第二個 enum 偏好來的時候做的卻是再抄一份。
/// 真正該只有一份的是這個決定：**磁碟上讀到認不得的字串時該怎麼辦**。
///
/// 答案是「回 `defaultValue`」，理由與 `BoolPreference` 用 `object(forKey:)` 的理由同族：
/// 使用者手動改壞 plist、或舊版本寫過別的格式時，不能 crash，也不能靜默變成別的值。
struct RawValuePreference<Value: RawRepresentable> where Value.RawValue == String {
    let key: String
    /// 缺鍵、或存了無法辨識的字串時回這個值。
    let defaultValue: Value
    /// 已知舊字面 → 新值的**明確**遷移表。空表是常態；有東西時代表「我們知道磁碟上
    /// 可能有這個舊值」，而不是碰巧被 `?? defaultValue` 那條兜底路徑接住——兩者結果
    /// 可能一樣，但寫出來的那份在未來改動時看得見。
    var legacyAliases: [String: Value] = [:]

    func load(from defaults: UserDefaults) -> Value {
        guard let raw = defaults.string(forKey: key) else { return defaultValue }
        if let value = Value(rawValue: raw) { return value }
        return legacyAliases[raw] ?? defaultValue
    }

    func persist(_ value: Value, to defaults: UserDefaults) {
        defaults.set(value.rawValue, forKey: key)
    }
}
