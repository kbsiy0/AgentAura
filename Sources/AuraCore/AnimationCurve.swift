/// 動畫 alpha 曲線與週期。自 `LEDStripView.alpha(for:phase:)` 與
/// `AnimationDriver.period(of:)` 搬入（T03）——搬完後 App 層不得再對
/// `IconAnimation` 做 switch，見 spec §6 `appLayerNeverSwitchesOnIconAnimation`。
public enum AnimationCurve {
    /// `phase` 是 0…1 的循環位置。breathe 用三角波（比 sin 便宜，低幀率下看起來一樣）；
    /// doubleBlink 一個週期內「亮 亮 暗」——兩次短閃後留一段暗。
    public static func alpha(for animation: IconAnimation, phase: Double) -> Double {
        switch animation {
        case .none:
            return 1.0
        case .breathe(_, let lo, let hi):
            let t = phase < 0.5 ? phase * 2 : (1 - phase) * 2
            return lo + (hi - lo) * t
        case .doubleBlink:
            switch phase {
            case ..<0.14, 0.28..<0.42: return 1.0
            default:                   return 0.08
            }
        }
    }

    public static func period(of animation: IconAnimation) -> Double? {
        switch animation {
        case .none: return nil
        case .breathe(let p, _, _): return p
        case .doubleBlink(let p): return p
        }
    }
}
