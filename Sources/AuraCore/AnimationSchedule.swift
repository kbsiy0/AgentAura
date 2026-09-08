/// 影響「該不該動」的外部條件。
///
/// 做成一個值而不是散在 AppKit callback 裡的 if：省電規則因此可以被測試，
/// 而且新增一個抑制條件時只有一處要改。
public struct DisplayEnvironment: Equatable, Sendable {
    public var screenAsleep: Bool
    public var iconVisible: Bool
    public var reduceMotion: Bool

    public init(screenAsleep: Bool = false, iconVisible: Bool = true, reduceMotion: Bool = false) {
        self.screenAsleep = screenAsleep
        self.iconVisible = iconVisible
        self.reduceMotion = reduceMotion
    }

    /// 任一條件成立就不該動。
    public var suppressesAnimation: Bool { screenAsleep || !iconVisible || reduceMotion }
}

public enum AnimationSchedule {

    /// 重繪間隔（秒）；`nil` 表示不該排程任何重繪。
    ///
    /// 幀率**一律**取自 `AppearancePolicy`，不在這裡另定一份 —— 兩處各自定義
    /// 幀率就會 drift，而 DoD 是照 `IconAppearance.targetFPS` 量的。
    public static func interval(for icon: IconState,
                                in env: DisplayEnvironment) -> Double? {
        guard !env.suppressesAnimation else { return nil }
        let fps = AppearancePolicy.appearance(for: icon, reduceMotion: env.reduceMotion).targetFPS
        guard fps > 0 else { return nil }
        return 1.0 / Double(fps)
    }
}
