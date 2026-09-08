import AppKit
import AuraCore

@MainActor
protocol IconRendering: AnyObject {
    func apply(_ appearance: IconAppearance, phase: Double)
}

/// 擁有 `NSStatusItem`，把 `IconAppearance` 交給 view 畫。
@MainActor
final class StatusItemController: IconRendering {
    private let item: NSStatusItem
    private let strip = LEDStripView()

    init() {
        item = NSStatusBar.system.statusItem(withLength: LEDStripView.preferredWidth + 8)
        strip.frame = NSRect(x: 4, y: 0,
                             width: LEDStripView.preferredWidth,
                             height: item.statusBar?.thickness ?? 22)
        item.button?.addSubview(strip)
        item.button?.toolTip = "AgentAura"
    }

    var isVisible: Bool { item.isVisible }

    func apply(_ appearance: IconAppearance, phase: Double) {
        strip.update(appearance, phase: phase)
        item.button?.toolTip = Self.tooltip(for: appearance)
    }

    static func tooltip(for a: IconAppearance) -> String {
        if a.attentionCount > 0 { return "\(a.attentionCount) 個需要你 · \(a.liveCount) 個在跑" }
        if a.liveCount > 0 { return "\(a.liveCount) 個 session 在跑" }
        return "沒有活著的 session"
    }
}
