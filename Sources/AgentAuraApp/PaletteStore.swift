import Foundation
import AuraCore

/// `UserDefaults` 搬運層——只讀 `Activity.customizable` 四個 key，`decode`/`encode`
/// 純函式在 AuraCore（spec §2 設計選擇 1）。「idle 不可覆寫」由 `PaletteCodec.decode`
/// 純函式層防禦（AuraCore gate `decodeFallsBackPerKey` 守），這裡不重複儀器。
@MainActor
final class PaletteStore {
    private let defaults: UserDefaults
    private(set) var palette: IconPalette
    var onChange: (() -> Void)?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        var overrides: [Activity: String] = [:]
        for activity in Activity.customizable {
            overrides[activity] = defaults.string(forKey: Self.key(for: activity))
        }
        palette = PaletteCodec.decode(overrides: overrides)
    }

    /// 先更新記憶體並通知（icon／面板即時反映），**再**落盤。
    func set(_ color: RGBA, for activity: Activity) {
        guard Activity.customizable.contains(activity) else { return }   // idle 不可改（D-a）；persist 也不會寫它
        palette = palette.with(activity, color: color)
        onChange?()
        persist()
    }

    func reset() {
        palette = .default
        onChange?()
        persist()
    }

    /// `encode(palette)` 出來的 key 寫入 hex；customizable 中不在其中的（＝已回到預設）remove。
    private func persist() {
        let encoded = PaletteCodec.encode(palette)
        for activity in Activity.customizable {
            let key = Self.key(for: activity)
            if let hex = encoded[activity] {
                defaults.set(hex, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    private static func key(for activity: Activity) -> String {
        "AgentAuraColor.\(activity.rawValue)"
    }
}
