import AppKit
import AuraCore

/// 照 `AnimationSchedule` 的決定推進 `phase` 並要求重繪。
///
/// 它**不決定**該不該動 —— 那是 `AnimationSchedule` 的職責。它只負責：
/// 監聽環境變化、把新的環境交給 `AnimationSchedule`、依回傳的間隔排程。
@MainActor
final class AnimationDriver {
    private var timer: Timer?
    private var phase: Double = 0
    private var icon: IconState = .empty
    private var env = DisplayEnvironment()
    private let onFrame: (IconAppearance, Double) -> Void

    init(onFrame: @escaping (IconAppearance, Double) -> Void) {
        self.onFrame = onFrame
        // 觀察者的 closure 是 @Sendable，但我們指定 queue: .main，所以實際一定在
        // main actor 上執行 —— 用 assumeIsolated 把這個事實告訴編譯器。
        // 少了它會得到一串 "capture of 'self' with non-Sendable type" 警告。
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                       object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update { $0.screenAsleep = true } }
        }
        nc.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                       object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update { $0.screenAsleep = false } }
        }
        nc.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                       object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.update {
                    $0.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                }
            }
        }
        env.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func setIcon(_ icon: IconState) {
        self.icon = icon
        reschedule()
    }

    func setIconVisible(_ visible: Bool) {
        update { $0.iconVisible = visible }
    }

    private func update(_ mutate: (inout DisplayEnvironment) -> Void) {
        mutate(&env)
        reschedule()
    }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        let appearance = AppearancePolicy.appearance(for: icon, reduceMotion: env.reduceMotion)
        // 靜態狀態也要畫一次，否則停止動畫後畫面留在上一格
        onFrame(appearance, 0)

        guard let interval = AnimationSchedule.interval(for: icon, in: env) else { return }
        let period = Self.period(of: appearance.animation) ?? 1.0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.phase = (self.phase + interval / period).truncatingRemainder(dividingBy: 1)
                self.onFrame(appearance, self.phase)
            }
        }
    }

    static func period(of animation: IconAnimation) -> Double? {
        switch animation {
        case .none: return nil
        case .breathe(let p, _, _): return p
        case .doubleBlink(let p): return p
        }
    }
}
