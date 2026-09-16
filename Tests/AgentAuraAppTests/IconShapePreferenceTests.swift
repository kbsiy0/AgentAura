import Testing
import Foundation
import AuraCore
@testable import AgentAuraApp

/// T32：造型偏好的 `UserDefaults` 搬運層。**預設 `.ledStrip`**（design doc D-3：不驚動既有
/// 使用者），缺鍵／存了無法辨識的字串都要 fallback 回 `.ledStrip`。
///
/// **reuse#4 之後改測生產物件本身**：搬運層收斂成泛型 `RawValuePreference` 之後，
/// 預設值與遷移表都移到組裝點（`AppDelegate.iconShapePreference`）。如果這裡繼續自己
/// `RawValuePreference(key:defaultValue:legacyAliases:)` 建一個來測，測到的就是測試自己
/// 抄的那份表——生產的表改壞了也照樣全綠。所以一律用生產物件，只換一個拋棄式的
/// `UserDefaults` suite（鍵名相同，但寫進臨時 domain，不碰使用者的真實偏好）。
@MainActor
@Suite("造型偏好：預設 .ledStrip")
struct IconShapePreferenceTests {

    func freshDefaults() -> (UserDefaults, String) {
        let suite = "io.agentaura.tests.iconshapepref.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    var pref: RawValuePreference<IconShape> { AppDelegate.iconShapePreference }
    var key: String { AppDelegate.iconShapeKey }

    @Test("缺鍵時 load 回 .ledStrip")
    func missingKeyDefaultsToLedStrip() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(pref.load(from: defaults) == .ledStrip)
    }

    @Test("persist 之後 load 讀回同一個值——IconShape.allCases 逐一往返，不是單一代表值")
    func persistRoundTrips() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        for shape in IconShape.allCases {
            pref.persist(shape, to: defaults)
            #expect(pref.load(from: defaults) == shape, "persist(\(shape)) 之後 load 應回 \(shape)")
        }
    }

    @Test("存了無法辨識的字串時 load 回 .ledStrip（不是 crash 也不是別的造型）")
    func unrecognizedStoredValueDefaultsToLedStrip() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("這不是合法的 rawValue", forKey: key)
        #expect(pref.load(from: defaults) == .ledStrip)
    }

    /// T36 加入彩虹貓（`nyanCat` → 改名 `rainbowCat`）、T37 整個移除。兩個字面都可能留在
    /// 已經選過它的使用者磁碟上，必須**明確**降級到預設，而不是掉進「讀不懂就算了」的
    /// 兜底路徑——結果一樣，但列在遷移表裡代表「我們知道有這個舊值」。
    ///
    /// **mutation**：把 `AppDelegate.iconShapePreference` 的 `legacyAliases` 清空，
    /// `bothLegacyValuesAreListedExplicitly` 會紅（兜底路徑仍讓 `load` 回 `.ledStrip`，
    /// 所以光測 `load` 的結果測不出差別——這正是要分開斷言遷移表內容的原因）。
    @Test("彩虹貓的兩個舊字面都明確列在遷移表裡，且 load 回預設")
    func bothLegacyValuesAreListedExplicitly() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        for legacy in ["nyanCat", "rainbowCat"] {
            #expect(pref.legacyAliases[legacy] == .ledStrip, """
                舊值 "\(legacy)" 不在遷移表裡。它今天仍會經由 `?? defaultValue` 兜底回
                `.ledStrip`，所以看起來沒事——但那是碰巧，不是我們知道它存在。
                """)
            defaults.set(legacy, forKey: key)
            #expect(pref.load(from: defaults) == .ledStrip, "舊值 \(legacy) 應降級到預設")
        }
    }
}
