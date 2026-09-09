import AppKit
import AuraCore

/// 形態 A2：menu bar 裡的 8 顆迷你 LED 燈條 + 不透明底板（spec §4.1）。
///
/// `phase` 由 `AnimationDriver` 推進（0…1 的循環位置），view 自己不持有計時器 ——
/// 這樣「多久畫一次」的決策留在可測的 `AnimationSchedule`，view 只負責畫。
@MainActor
final class LEDStripView: NSView, IconDrawing {
    /// 刻意不叫 `appearance` —— `NSView` 已有一個 `appearance: NSAppearance?`，
    /// 同名會得到「cannot override a property with type 'NSAppearance?'」。
    private var iconAppearance = AppearancePolicy.appearance(for: IconState.empty)
    private var phase: Double = 0

    static let ledCount = 8
    static let ledSize = CGSize(width: 3, height: 12)
    static let ledGap: CGFloat = 2
    /// LED 左邊界與底板描邊的間距，也是底板左／上下內距（spec §4.1）。
    static let plateInset: CGFloat = 4
    static let plateHeight: CGFloat = 18
    static let plateCornerRadius: CGFloat = 5
    /// 不透明 `#141416`（20,20,22）——背景無關，深淺模式一律（spec §4.1）。
    static let plateColor = NSColor(srgbRed: 20 / 255, green: 20 / 255, blue: 22 / 255, alpha: 1)

    /// view bounds 含底板（spec §4.1）——離屏畫布與生產畫布一致，r1 的「bounds 外擴」不再發生。
    static var preferredWidth: CGFloat { 42 }

    /// `IconDrawing` 要求 instance 版本。
    var preferredWidth: CGFloat { Self.preferredWidth }

    private var plateRect: NSRect {
        NSRect(x: 0, y: (bounds.height - Self.plateHeight) / 2,
               width: bounds.width, height: Self.plateHeight)   // 底板 = bounds（spec §4.1），不是常數
    }

    /// 第 `index` 顆 LED 的畫布矩形，供測試從幾何推導取樣點，不寫魔術數字。
    func ledRect(at index: Int) -> NSRect {
        let x = Self.plateInset + CGFloat(index) * (Self.ledSize.width + Self.ledGap)
        let y = (bounds.height - Self.ledSize.height) / 2
        return NSRect(x: x, y: y, width: Self.ledSize.width, height: Self.ledSize.height)
    }

    func update(_ appearance: IconAppearance, phase: Double) {
        self.iconAppearance = appearance
        self.phase = phase
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let plate = plateRect
        Self.plateColor.setFill()
        NSBezierPath(roundedRect: plate, xRadius: Self.plateCornerRadius, yRadius: Self.plateCornerRadius).fill()

        // 描邊路徑內縮 0.25pt，否則外側 0.25pt 會被 bounds 裁掉（spec §4.1）。
        let strokePath = NSBezierPath(roundedRect: plate.insetBy(dx: 0.25, dy: 0.25),
                                      xRadius: Self.plateCornerRadius, yRadius: Self.plateCornerRadius)
        strokePath.lineWidth = 0.5
        NSColor.white.withAlphaComponent(0.10).setStroke()
        strokePath.stroke()

        // 顏色與 alpha 全部來自 IconAppearance —— 不再自己 switch activity、
        // 不再自己算曲線，idle 也無 per-state 特例（spec §4.1）。
        let c = iconAppearance.color
        let alpha = c.a * AnimationCurve.alpha(for: iconAppearance.animation, phase: phase)
        let ledColor = NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha)
        for i in 0..<Self.ledCount {
            ledColor.setFill()
            NSBezierPath(roundedRect: ledRect(at: i), xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}
