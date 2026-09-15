import Foundation
import AuraCore

/// D-2：語言偏好的 `UserDefaults` 搬運層——比照 `BoolPreference`（形狀相同：注入 `defaults`
/// 的小型別），值域換成 `Language`。**預設英文**：缺鍵或存了無法辨識的字串（例如舊版本
/// 寫過的格式，或使用者手動改壞 plist）一律 fallback 回 `.english`，不跟隨系統語言
/// （design doc D-2——中文系統上第一次啟動也是英文）。
struct LanguagePreference {
    let key: String

    func load(from defaults: UserDefaults) -> Language {
        guard let raw = defaults.string(forKey: key), let language = Language(rawValue: raw) else {
            return .english
        }
        return language
    }

    func persist(_ value: Language, to defaults: UserDefaults) {
        defaults.set(value.rawValue, forKey: key)
    }
}
