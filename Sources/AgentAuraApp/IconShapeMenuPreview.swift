import AppKit
import AuraCore

/// T35：造型選單開著時讓每一項縮圖動起來——使用者原話「你做一個動畫觸發機制，
/// 讓我可以快速看到套用該圖示的效果」。不必選下去、關掉選單、開回面板才看得到動畫。
///
/// **`NSMenu.popUp` 是阻塞呼叫，執行期間 run loop 切到 `.eventTracking` mode**。
/// `AnimationDriver` 那顆給選單列真正 icon 用的 timer 是
/// `Timer.scheduledTimer(withTimeInterval:repeats:)`，只掛在 `.default` mode——
/// 這是給一般視窗用的，選單開著時不會觸發。這裡改用
/// `RunLoop.main.add(_:forMode: .common)`：`.common` 是 AppKit 內建、包含
/// `.eventTracking` 在內的模式集合。**已用真的 `NSApplication` + 真的
/// `NSMenu.popUp` 實測過**（scratchpad `runloop_probe3.swift`）：`.common` mode
/// 的 timer 在選單開著期間真的觸發（5 次，且成功呼叫 `menu.cancelTracking()`
/// 自己把選單關掉）；純 command-line、沒有真的 `NSApplication`／沒有真的
/// `NSMenu.popUp` 在跑的對照組（`runloop_probe.swift`／`runloop_probe2.swift`）
/// 量到的是 0 —— 證明「有沒有真的 NSMenu 在 track」才是關鍵，不是 mode 本身。
///
/// 動畫參數（間隔／曲線）一律來自 `IconAppearance.targetFPS` 與 `AnimationCurve`
/// ——不自己定義週期（D-2 的延伸：造型不決定「動多快」，這裡也不決定）。
/// `targetFPS == 0` 時完全不排程：涵蓋「這個造型本來就是 `.none` 動畫」
/// 與「呼叫端已經把使用者的減少動態偏好併進 appearance」兩種情況，兩者都不該動
/// ——滿足可及性承諾，不是裝飾。
///
/// **不會影響選單列上真正的 icon**：這個型別完全不持有 `StatusItemController`／
/// `AnimationDriver` 的任何參照，只認得傳進來的 `NSMenuItem` 陣列——結構上不可能
/// 碰到真正的 icon 或使用者當下的 activity。
@MainActor
final class IconShapeMenuPreview {
    /// internal（不是 private）：測試要確認 `start()`／`stop()` 真的排程／真的收掉。
    private(set) var timer: Timer?
    /// internal：測試直接呼叫 `tick(step:)`，不依賴真的 timer 觸發時機——
    /// 「量測絕對時間內會不會觸發」屬於這個 codebase 已經被咬過三次的 flaky 類型
    /// （CLAUDE.md「這個 codebase 的 gate 哲學」第 5 條），機制本身已經用上面
    /// doc comment 提到的 scratchpad 腳本實測過，這裡的 gate 改測「相位真的推進、
    /// 真的重畫」，不重複測「timer 準不準時」。
    private(set) var phase: Double = 0
    private let items: [(shape: IconShape, item: NSMenuItem)]
    private let appearance: IconAppearance
    private let showsPlate: Bool

    init(items: [(shape: IconShape, item: NSMenuItem)], appearance: IconAppearance, showsPlate: Bool) {
        self.items = items
        self.appearance = appearance
        self.showsPlate = showsPlate
    }

    /// `targetFPS == 0` 時不排程，縮圖停在 `IconShapeMenu.present` 已經畫好的
    /// 那張靜態全不透明縮圖（T34），不會動。
    func start() {
        guard appearance.targetFPS > 0 else { return }
        let interval = 1.0 / Double(appearance.targetFPS)
        let period = AnimationCurve.period(of: appearance.animation) ?? 1.0
        // **顯式跳回 main actor**，不要靠編譯器推斷。
        // `Timer` 的 block 是 nonisolated `@Sendable`；Swift 6.3 在這個位置推得出
        // main-actor 隔離，**Swift 6.1.2 推不出來**——CI（macOS 15 runner）因此編不過，
        // 而本機（6.3.3）完全看不出問題。任何用 Xcode 16.x 的人都會撞到。
        //
        // 用 `Task { @MainActor in }` 而不是 `MainActor.assumeIsolated`：後者在 6.1.2 上
        // 因為泛型回傳值的 Sendable 約束而編不過（實測 CI 回報
        // `non-sendable result type 'T'`，還附帶一次編譯器 fatalError）。
        // 代價是每格多一次 async hop，而這顆 timer 只在選單開著時存在，可以接受。
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(step: interval / period) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 選單關閉（`popUp` 回傳）後立刻呼叫——比照 `QuitKeyMonitor`／`PanelDismissMonitor`
    /// 的既有形狀，這個 codebase 對「沒收掉的全域監看／計時器」很敏感。
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func tick(step: Double) {
        phase = (phase + step).truncatingRemainder(dividingBy: 1)
        for (shape, item) in items {
            item.image = IconShapePreview.image(for: shape, appearance: appearance, showsPlate: showsPlate, phase: phase)
        }
    }
}
