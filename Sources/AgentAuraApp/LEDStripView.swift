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
    /// T16（修正 spec §4.1 算術錯誤）：8 顆燈＋7 個間隙的總跨距——原文寫「8×3 + 7×2 = 34」，
    /// 但 8×3 + 7×2 = **38**，不是 34；`preferredWidth` 曾照著錯的 34（+ inset 4×2 = 42）硬寫死，
    /// 導致最後一顆燈的右邊界恰好貼齊底板右緣（右邊距 0pt），燈條被推向右側（team-lead 實測、
    /// 使用者回報「底面板其實在圖片的右邊，有點跑版」）。這裡改推導，不再重複同一個錯字面值。
    static var ledSpan: CGFloat { CGFloat(ledCount) * ledSize.width + CGFloat(ledCount - 1) * ledGap }
    /// T16：底板四邊等寬——與垂直邊距 `(plateHeight - ledSize.height) / 2 = 3` 對齊，
    /// 左右邊距因此也改成 3（原本的 4 是算錯的 `preferredWidth` 反推出的巧合值，不是刻意選的）。
    static let plateInset: CGFloat = 3
    static let plateHeight: CGFloat = 18
    static let plateCornerRadius: CGFloat = 5
    /// 不透明 `#141416`（20,20,22）——背景無關，深淺模式一律（spec §4.1）。
    static let plateColor = NSColor(srgbRed: 20 / 255, green: 20 / 255, blue: 22 / 255, alpha: 1)

    /// view bounds 含底板（spec §4.1）——離屏畫布與生產畫布一致，r1 的「bounds 外擴」不再發生。
    /// **從 `ledSpan`／`plateInset` 推導，不寫字面值**——這正是原本 42 這個錯數字被凍住的病根
    /// （見上面 `ledSpan` 的說明；`statusItemWidthFollowsRenderer` 的 mutation 記錄同一件事）。
    static var preferredWidth: CGFloat { ledSpan + plateInset * 2 }

    /// `IconDrawing` 要求 instance 版本。
    var preferredWidth: CGFloat { Self.preferredWidth }

    /// T16：使用者可關掉底板（`OptionsMenuModel` 的「燈條底板」列）——預設 true。
    /// 寬度／LED 位置不受影響（`plateInset` 仍然是幾何錨點，只是關掉時不描邊填色）。
    private(set) var showsPlate = true

    /// internal（不是 private）：`LEDPlateSymmetryTests`（T16）要從外面讀它，跟四邊邊距比對。
    var plateRect: NSRect {
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

    /// T16：`false` 時只畫 LED，不畫底板填色／描邊——寬度與 LED 位置不變（`plateInset`
    /// 仍是幾何錨點，不是「拿掉底板就把 LED 攤平置中」）。自己要求重繪，同 `update` 的模式。
    func setShowsPlate(_ shows: Bool) {
        showsPlate = shows
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if showsPlate {
            let plate = plateRect
            Self.plateColor.setFill()
            NSBezierPath(roundedRect: plate, xRadius: Self.plateCornerRadius, yRadius: Self.plateCornerRadius).fill()

            // 描邊路徑內縮 0.25pt，否則外側 0.25pt 會被 bounds 裁掉（spec §4.1）。
            let strokePath = NSBezierPath(roundedRect: plate.insetBy(dx: 0.25, dy: 0.25),
                                          xRadius: Self.plateCornerRadius, yRadius: Self.plateCornerRadius)
            strokePath.lineWidth = 0.5
            NSColor.white.withAlphaComponent(0.10).setStroke()
            strokePath.stroke()
        }

        // 顏色與 alpha 全部來自 IconAppearance —— 不再自己 switch activity、
        // 不再自己算曲線，idle 也無 per-state 特例（spec §4.1）。
        let c = iconAppearance.color
        let alpha = c.a * AnimationCurve.alpha(for: iconAppearance.animation, phase: phase)
        // E13（/simplify 波次2，reuse#13）：改走 `ColorBridge` 的 `NSColor(rgba:alpha:)`——
        // 不再自己手寫 `NSColor(srgbRed:...)` 繞過既有的唯一轉換點。
        let ledColor = NSColor(rgba: c, alpha: alpha)
        for i in 0..<Self.ledCount {
            ledColor.setFill()
            NSBezierPath(roundedRect: ledRect(at: i), xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}
