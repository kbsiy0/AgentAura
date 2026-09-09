// Sources/AgentAuraApp/StatusItemController.swift
import AppKit
import SwiftUI      // NSHostingController
import AuraCore

/// `AppDelegate` 依賴的選單列介面。
///
/// **這個 protocol 存在的理由是可測性，不是抽象癖。** spec §5.2 要求一條
/// composition-root smoke：「`StatusItemController` **真的**收到 `IconState` 更新
/// （spy 斷言呼叫確實發生，不是被 catch-all 吞掉）」。沒有這個縫，
/// `AppDelegate` 就無法被注入 spy —— 而最終 review 實測：把 `graph.start()`
/// 與 liveness timer 整段註解掉（產品完全不動），220/220 全綠。
@MainActor
protocol IconRendering: AnyObject {
    func apply(_ appearance: IconAppearance, phase: Double)
    var isVisible: Bool { get }
    func attachPopover()
    func setPanel(title: String, rows: [PanelRow])
    var onOpen: (() -> Void)? { get set }
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

    private let popover = NSPopover()
    var onOpen: (() -> Void)?

    func attachPopover() {
        popover.behavior = .transient
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
    }

    func setPanel(title: String, rows: [PanelRow]) {
        popover.contentViewController = NSHostingController(
            rootView: PanelView(title: title, rows: rows))
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // 開啟即 acknowledge（D2）—— 面板是唯一互動，用它當確認手勢
            onOpen?()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
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
