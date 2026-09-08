import AppKit
import AuraCore

/// 形態 A：menu bar 裡的 8 顆迷你 LED 燈條。
///
/// `phase` 由 `AnimationDriver` 推進（0…1 的循環位置），view 自己不持有計時器 ——
/// 這樣「多久畫一次」的決策留在可測的 `AnimationSchedule`，view 只負責畫。
@MainActor
final class LEDStripView: NSView {
    /// 刻意不叫 `appearance` —— `NSView` 已有一個 `appearance: NSAppearance?`，
    /// 同名會得到「cannot override a property with type 'NSAppearance?'」。
    private var iconAppearance = AppearancePolicy.appearance(for: IconState.empty)
    private var phase: Double = 0

    static let ledCount = 8
    static let ledWidth: CGFloat = 3
    static let ledGap: CGFloat = 2
    static let ledHeight: CGFloat = 12

    static var preferredWidth: CGFloat {
        CGFloat(ledCount) * ledWidth + CGFloat(ledCount - 1) * ledGap
    }

    func update(_ appearance: IconAppearance, phase: Double) {
        self.iconAppearance = appearance
        self.phase = phase
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let color = Self.color(for: iconAppearance.activity)
        let alpha = Self.alpha(for: iconAppearance.animation, phase: phase)
        var x: CGFloat = 0
        let y = (bounds.height - Self.ledHeight) / 2
        for _ in 0..<Self.ledCount {
            let r = NSRect(x: x, y: y, width: Self.ledWidth, height: Self.ledHeight)
            color.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: r, xRadius: 1.5, yRadius: 1.5).fill()
            x += Self.ledWidth + Self.ledGap
        }
    }

    /// 顏色跟隨 menu bar 的深淺色 —— `NSColor` 的 system color 會自己處理。
    static func color(for activity: Activity) -> NSColor {
        switch activity {
        case .idle:    return .tertiaryLabelColor
        case .working: return .systemBlue
        case .waiting: return .systemOrange
        case .done:    return .systemGreen
        case .error:   return .systemRed
        }
    }

    static func alpha(for animation: IconAnimation, phase: Double) -> CGFloat {
        switch animation {
        case .none:
            return 1.0
        case .breathe(_, let lo, let hi):
            // 三角波比 sin 便宜，且在低幀率下看起來一樣
            let t = phase < 0.5 ? phase * 2 : (1 - phase) * 2
            return CGFloat(lo + (hi - lo) * t)
        case .doubleBlink:
            // 一個週期內：亮 亮 暗 —— 兩次短閃後留一段暗
            switch phase {
            case ..<0.14, 0.28..<0.42: return 1.0
            default:                   return 0.08
            }
        }
    }
}
