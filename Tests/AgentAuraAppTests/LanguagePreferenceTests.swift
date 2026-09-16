import Testing
import Foundation
import AuraCore
@testable import AgentAuraApp

/// D-2：語言偏好的 `UserDefaults` 搬運層——比照 `BoolPreference` 的形狀，值域換成
/// `Language`。**預設英文**，且缺鍵／存了無法辨識的字串都要 fallback 回英文，不跟隨
/// 系統語言（design doc D-2：中文系統上第一次啟動也是英文）。
/// **reuse#4 之後改測生產物件本身**：預設值移到組裝點（`AppDelegate.languagePreference`）
/// 之後，測試若自己建一個 `RawValuePreference(key:defaultValue:)`，驗到的就是測試自己寫的
/// `.english`——生產那邊改成別的語言也照樣全綠。理由同 `IconShapePreferenceTests`。
@MainActor
@Suite("語言偏好：預設英文，不跟隨系統語言")
struct LanguagePreferenceTests {

    var pref: RawValuePreference<Language> { AppDelegate.languagePreference }
    var key: String { AppDelegate.languageKey }

    func freshDefaults() -> (UserDefaults, String) {
        let suite = "io.agentaura.tests.langpref.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test("缺鍵時 load 回 .english")
    func missingKeyDefaultsToEnglish() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(pref.load(from: defaults) == .english)
    }

    @Test("persist 之後 load 讀回同一個值（兩個方向都測，不是單一代表值）")
    func persistRoundTrips() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        pref.persist(.traditionalChinese, to: defaults)
        #expect(pref.load(from: defaults) == .traditionalChinese)

        pref.persist(.english, to: defaults)
        #expect(pref.load(from: defaults) == .english)
    }

    @Test("存了無法辨識的字串時 load 回 .english（不是 crash 也不是別的語言）")
    func unrecognizedStoredValueDefaultsToEnglish() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("français", forKey: "TestLang")
        #expect(pref.load(from: defaults) == .english)
    }
}
