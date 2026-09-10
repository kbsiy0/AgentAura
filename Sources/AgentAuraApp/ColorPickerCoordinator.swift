import AppKit
import AuraCore

/// `NSColorPanel` 橋接：把系統色板的拖曳結果轉成 `RGBA`，並在色板關閉時解除面板釘住
/// （D-i）。`NSObject` 子類——`changeColor(_:)` 要能當 `NSColorPanel` 的 target-action。
@MainActor
final class ColorPickerCoordinator: NSObject {
    var onPick: ((Activity, RGBA) -> Void)?
    var onEnd: (() -> Void)?
    private(set) var endCount = 0

    private var activeActivity: Activity?
    private var willCloseToken: NSObjectProtocol?

    override init() {
        super.init()
        // 觀察者的 closure 是 @Sendable，但我們指定 queue: .main，所以實際一定在
        // main actor 上執行 —— 用 assumeIsolated 把這個事實告訴編譯器（同 AnimationDriver）。
        // `object: nil` 再在 block 內過濾——若傳 `NSColorPanel.shared` 當 object，會在 launch 同步區就把整個
        // 色板 UI 建出來（review-t0203 I2 實測 +120 ms，加在第一顆燈亮起之前）。改色是低頻操作，成本延到第一次 pick。
        willCloseToken = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard note.object is NSColorPanel else { return }
            MainActor.assumeIsolated {
                self?.activeActivity = nil
                self?.endCount += 1
                self?.onEnd?()
            }
        }
    }

    /// 開啟系統色板並指向 `activity`；`present` 為 false 時只設定不 `orderFront`（供測試離屏用）。
    ///
    /// `NSColorPanel.color` 的 setter 在 target／action 已設定時會同步呼叫該 action
    /// （已實測確認，與 `isContinuous` 無關）——若沿用上一次 `pick` 留下的 target 去設定
    /// 這次的「priming」色，會讓 `changeColor` 用還沒被使用者改過的 `current` 誤觸發
    /// `onPick`。先清空 target 再設色、設完再接回，讓 priming 這一步保證靜默。
    func pick(_ activity: Activity, current: RGBA, present: Bool = true) {
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.hidesOnDeactivate = false
        panel.color = NSColor(rgba: current)
        activeActivity = activity
        panel.setTarget(self)
        panel.setAction(#selector(changeColor(_:)))
        if present {
            panel.orderFront(nil)
        }
    }

    /// 三關 guard：`sender` 必須是 `NSColorPanel`、`activeActivity` 非 nil、色轉 sRGB 成功。
    @objc func changeColor(_ sender: Any?) {
        guard let panel = sender as? NSColorPanel,
              let activity = activeActivity,
              let color = Self.rgba(from: panel.color) else { return }
        onPick?(activity, color)
    }

    /// 把 `NSColor` 轉成 sRGB `RGBA`；轉不過（如 pattern image）回 nil。**alpha 一律強制為 1**：
    /// `showsAlpha = false` 只是隱藏滑桿，不會把色板現有顏色的 alpha 正規化（review-t0203 I1 實測 a=0.5 會一路進 palette，
    /// 而 `hex()` 又丟掉 alpha → 這次 session 半亮、重啟後全亮）。四色 a 恆 1 的不變式在此**單一收口**強制。
    static func rgba(from color: NSColor) -> RGBA? {
        guard let converted = color.usingColorSpace(.sRGB) else { return nil }
        return RGBA(r: converted.redComponent, g: converted.greenComponent,
                    b: converted.blueComponent, a: 1)
    }

    func detach() {
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
        activeActivity = nil
        if let token = willCloseToken {
            NotificationCenter.default.removeObserver(token)
            willCloseToken = nil
        }
    }
}
