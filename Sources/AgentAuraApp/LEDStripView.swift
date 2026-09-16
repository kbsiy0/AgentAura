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
    /// 底板色。字面住在 `IconPlate.colorRGBA`（兩個造型 conformer 共用的同一份），
    /// 這裡只是它的 `NSColor` 面貌——simplify#B2 之前是反過來的，導致同一組數字有三份。
    static let plateColor = IconPlate.color

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
    /// 底板矩形——幾何收在 `IconPlate.rect(in:)`，兩個 `IconDrawing` conformer 共用同一份
    /// （reuse#1：原本各寫一份，SF Symbol 那份畫滿整個 bounds，在選單列上高度就對不上）。
    /// 仍是 `LEDStripView` 的公開成員，`LEDPlateSymmetryTests` 讀的還是它。
    var plateRect: NSRect { IconPlate.rect(in: bounds) }

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
        // 底板繪製收在 `IconPlate.draw(in:)`——原本這裡與 `IconPlate` 各有一份逐行平行的
        // fill → inset → stroke，兩份已經漂開過一次（reuse#1）。
        if showsPlate { IconPlate.draw(in: plateRect) }

        // 顏色與 alpha 全部來自 IconAppearance —— 不自己 switch activity、不自己算曲線，
        // idle 也無 per-state 特例（spec §4.1）。公式本身收在 `ColorBridge` 的
        // `NSColor(appearance:phase:)`，與 `SFSymbolIconView` 共用同一份（reuse#3）。
        let ledColor = NSColor(appearance: iconAppearance, phase: phase)
        for i in 0..<Self.ledCount {
            ledColor.setFill()
            NSBezierPath(roundedRect: ledRect(at: i), xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}
