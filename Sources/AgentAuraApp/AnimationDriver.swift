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
    private var palette: IconPalette = .default
    private var env = DisplayEnvironment()
    private let onFrame: (IconAppearance, Double) -> Void
    /// B5：系統值與使用者偏好各自保存，`env.reduceMotion` 永遠是兩者的 OR
    /// （`setUserReduceMotion` 的理由）——系統已強制時使用者關掉也沒用，這是刻意的。
    ///
    /// E2（/simplify 波次2，reuse#10）：`private(set)` 讓 `AppDelegate.refreshPanel`
    /// 讀這裡——這裡是系統值**唯一**由通知維護的即時持有者，不該再讓 `refreshPanel`
    /// 自己另外問一次 `NSWorkspace`（兩份讀取點／兩份狀態）。
    private(set) var systemReduceMotion = false
    private var userReduceMotion = false
    /// E2：系統值真的改變時通知 `AppDelegate` 重畫面板（比照 `PaletteStore.onChange`
    /// 的既有模式）——原本系統設定改了之後只有這裡自己重排動畫，沒有人呼叫
    /// `refreshPanel()`，Options 那一列的「開／關」與 subtitle 會停在舊值。
    var onEnvironmentChange: (() -> Void)?

    /// E4（/simplify 波次2，eff#12）：三個 block-based observer 的 token——由
    /// notification center 持有，`[weak self]` 只保證閉包內不強引用 self，註冊本身
    /// 永遠不會自己消失。同輩 `StatusItemController`／`ColorPickerCoordinator` 都有
    /// 對應的移除路徑，這裡原本沒有；`stop()` 補上，`AppDelegate.applicationWillTerminate`
    /// 呼叫（收尾動作各自獨立，user CLAUDE.md #8）。
    private var screenSleepToken: NSObjectProtocol?
    private var screenWakeToken: NSObjectProtocol?
    private var reduceMotionToken: NSObjectProtocol?

    init(onFrame: @escaping (IconAppearance, Double) -> Void) {
        self.onFrame = onFrame
        // 觀察者的 closure 是 @Sendable，但我們指定 queue: .main，所以實際一定在
        // main actor 上執行 —— 用 assumeIsolated 把這個事實告訴編譯器。
        // 少了它會得到一串 "capture of 'self' with non-Sendable type" 警告。
        let nc = NSWorkspace.shared.notificationCenter
        screenSleepToken = nc.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                       object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update { $0.screenAsleep = true } }
        }
        screenWakeToken = nc.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                       object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update { $0.screenAsleep = false } }
        }
        reduceMotionToken = nc.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                       object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.setSystemReduceMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            }
        }
        systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        env.reduceMotion = systemReduceMotion
    }

    /// E4（eff#4）：`icon` 沒變時整趟 `reschedule()`（timer 拆建＋壓相位回 0）純屬浪費，
    /// 高事件率下呼吸動畫還會被釘在相位 0 附近——這是效率浪費之外的可見副作用。
    func setIcon(_ icon: IconState) {
        guard icon != self.icon else { return }
        self.icon = icon
        reschedule()
    }

    /// Change 2：換 palette 要觸發重排（m4 交接 M9）。
    func setPalette(_ palette: IconPalette) {
        self.palette = palette
        reschedule()
    }

    func setIconVisible(_ visible: Bool) {
        update { $0.iconVisible = visible }
    }

    /// internal（不是 private）：`AnimationDriverGuardTests` 要能直接呼叫它驗證
    /// equality guard／`onEnvironmentChange`——真的系統「減少動態」值無法在測試裡控制
    /// （`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` 讀真的系統設定），
    /// 這是唯一能不靠切換真實系統設定就測到這條路徑的方法。
    func setSystemReduceMotion(_ on: Bool) {
        guard on != systemReduceMotion else { return }
        systemReduceMotion = on
        update { $0.reduceMotion = systemReduceMotion || userReduceMotion }
        onEnvironmentChange?()
    }

    /// B5：使用者在 Options 切的偏好——與系統值取 OR，不是獨立生效
    /// （`OptionsMenuModel.rows` 在系統強制時本來就把這一列畫成 disabled）。
    func setUserReduceMotion(_ on: Bool) {
        userReduceMotion = on
        update { $0.reduceMotion = systemReduceMotion || userReduceMotion }
    }

    /// E4：`mutate` 前後比較 `DisplayEnvironment`（已 `Equatable`）——沒變就不重排，
    /// 同一個理由（事件多但狀態沒變的常態情境，timer churn 歸零）。
    private func update(_ mutate: (inout DisplayEnvironment) -> Void) {
        let previous = env
        mutate(&env)
        guard env != previous else { return }
        reschedule()
    }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        let appearance = AppearancePolicy.appearance(for: icon, palette: palette, reduceMotion: env.reduceMotion)
        // 靜態狀態也要畫一次，否則停止動畫後畫面留在上一格
        onFrame(appearance, 0)

        guard let interval = AnimationSchedule.interval(for: icon, in: env) else { return }
        let period = AnimationCurve.period(of: appearance.animation) ?? 1.0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.phase = (self.phase + interval / period).truncatingRemainder(dividingBy: 1)
                self.onFrame(appearance, self.phase)
            }
        }
    }

    /// E4：測試 teardown／`AppDelegate.applicationWillTerminate` 用——移除三個
    /// block-based observer，同 `StatusItemController.removeFromStatusBar` 的理由。
    func stop() {
        let nc = NSWorkspace.shared.notificationCenter
        if let screenSleepToken { nc.removeObserver(screenSleepToken) }
        if let screenWakeToken { nc.removeObserver(screenWakeToken) }
        if let reduceMotionToken { nc.removeObserver(reduceMotionToken) }
        screenSleepToken = nil
        screenWakeToken = nil
        reduceMotionToken = nil
    }
}
