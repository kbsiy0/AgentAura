/// Menu bar icon 的動畫形式。
public enum IconAnimation: Equatable, Sendable {
    case none
    /// 透明度在 `min`…`max` 之間以 `period` 秒往復。
    case breathe(period: Double, min: Double, max: Double)
    /// 每 `period` 秒閃兩下。
    case doubleBlink(period: Double)
}

/// 一個 `IconState` 該長什麼樣。純資料，不含任何繪製。
public struct IconAppearance: Equatable, Sendable {
    public let activity: Activity
    public let animation: IconAnimation
    /// 建議重繪幀率。`0` 表示完全靜態，`AnimationDriver` 不該排程任何重繪。
    public let targetFPS: Int
    public let attentionCount: Int
    public let liveCount: Int

    public var needsAnimation: Bool { targetFPS > 0 }
}

/// 注意力預算（R4）—— **這是產品決策，所以放在可單元測試的地方**。
///
/// 規則：只有需要使用者行動的狀態才會動。使用者的常態是多 agent 併行、
/// 整夜跑 pipeline；若 `working` 也搶眼，menu bar 幾乎永遠在動，「動起來」
/// 就失去訊號價值，必須辨色才知道發生什麼事。
///
/// 換來三件事：常態安靜；**餘光就能判斷、不需辨色**；大多數時間零重繪。
public enum AppearancePolicy {

    public static func appearance(for icon: IconState,
                                 reduceMotion: Bool = false) -> IconAppearance {
        let (animation, fps) = reduceMotion
            ? (IconAnimation.none, 0)
            : motion(for: icon.activity)
        return IconAppearance(activity: icon.activity,
                              animation: animation,
                              targetFPS: fps,
                              attentionCount: icon.attentionCount,
                              liveCount: icon.liveCount)
    }

    static func motion(for activity: Activity) -> (IconAnimation, Int) {
        switch activity {
        case .idle, .done:
            // 完全靜態。done 是「你可以去看了」，不是「你被擋著」。
            return (.none, 0)
        case .working:
            // 常態：看得出在跑，但不搶注意力。週期長、對比低、幀率低。
            return (.breathe(period: 4.0, min: 0.35, max: 0.60), 10)
        case .waiting:
            // 需要行動：週期短、對比高，與 working 差 4 倍週期、3 倍對比。
            return (.breathe(period: 1.1, min: 0.20, max: 1.00), 30)
        case .error:
            // 需要行動，且形狀與 waiting 不同 —— 不必辨色也能區分。
            return (.doubleBlink(period: 1.1), 30)
        }
    }
}
