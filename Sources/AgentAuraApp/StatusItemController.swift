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
///
/// Change 2（panel-legend-palette）新增：`setPanel` 改吃 `PanelModel`（取代
/// `title:rows:`），加圖例改色三個入口——`onPickColor`／`onResetColors`／
/// `setPopoverPinned`（spec §2）。
@MainActor
protocol IconRendering: AnyObject {
    func apply(_ appearance: IconAppearance, phase: Double)
    var isVisible: Bool { get }
    func attachPopover()
    func setPanel(_ model: PanelModel)
    var onOpen: (() -> Void)? { get set }
    var onPickColor: ((Activity) -> Void)? { get set }
    var onResetColors: (() -> Void)? { get set }
    func setPopoverPinned(_ pinned: Bool)
}

/// 擁有 `NSStatusItem`，把 `IconAppearance` 交給 `drawing` 畫。
///
/// `drawing` 型別是 `any IconDrawing`，但只有一個 conformer（`LEDStripView`，A2 定案
/// 於 `docs/2026-09-09-m4-ab-decision.md`）——protocol 仍在是因為 composition-root
/// smoke 與像素 gate 經 `@testable import` 讀 `drawing` 斷言接線與繪製；protocol 的存在理由是 controller 不綁死 view 型別（spec §2）。
@MainActor
final class StatusItemController: IconRendering {
    private let item: NSStatusItem
    let drawing: any IconDrawing

    init() {
        item = NSStatusBar.system.statusItem(withLength: 0)
        let view = LEDStripView()
        drawing = view
        item.length = drawing.preferredWidth + 8
        view.frame = NSRect(x: 4, y: 0,
                            width: drawing.preferredWidth,
                            height: NSStatusBar.system.thickness)
        item.button?.addSubview(view)
        item.button?.toolTip = "AgentAura"
        panelOnPick = { [weak self] activity in self?.onPickColor?(activity) }
        panelOnReset = { [weak self] in self?.onResetColors?() }
    }

    /// 測試讀取用（`statusItemWidthFollowsRenderer`）。
    var statusItemLength: CGFloat { item.length }

    /// 測試 teardown 用；生產 controller 活到 app 結束，不需要呼叫。
    /// 不用 `deinit`——nonisolated deinit 碰非 Sendable 的 `NSStatusItem` 在 Swift 6 編不過。
    func removeFromStatusBar() {
        NSStatusBar.system.removeStatusItem(item)
    }

    private let popover = NSPopover()
    var onOpen: (() -> Void)?
    var onPickColor: ((Activity) -> Void)?
    var onResetColors: (() -> Void)?

    /// `PanelView` 的 `onPick`/`onReset` 綁到這兩個閉包（`init` 設好，轉發到
    /// `onPickColor`/`onResetColors`）——`controllerForwardsPanelCallbacks` 守這條轉發。
    var panelOnPick: (Activity) -> Void = { _ in }
    var panelOnReset: () -> Void = {}

    /// `setPanel` 只在第一次建 `NSHostingController`，之後只換 `rootView`（D-j）。
    private(set) var hostingController: NSHostingController<PanelView>?
    /// `setPanel` 每次真的重建／換 rootView 就 +1（instrumentation，見 spec §2）。
    private(set) var rootViewAssignments = 0
    private var lastModel: PanelModel?

    var popoverBehavior: NSPopover.Behavior { popover.behavior }

    func attachPopover() {
        popover.behavior = .transient
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        // review-t01 I3：先掛一個空 model，讓 `popover.contentViewController` 從一開始就非 nil——
        // `togglePopover` 在 `contentViewController == nil` 時呼叫 `NSPopover.show` 會丟
        // NSException 殺掉整個行程，不是「這次點擊沒反應」。
        setPanel(PanelModel.make(icon: .empty, sessions: [], palette: .default))
    }

    /// 首次建 `NSHostingController` 並設 `sizingOptions = [.preferredContentSize]`
    /// （macOS 13+，讓 `preferredContentSize` 隨 `rootView` 自動同步且會縮回——手動賦值會凍住，
    /// review r3 I-b 實測）；之後只換 `rootView`。`model` 未變就跳過（D-j：`isContinuous` 拖曳
    /// 每秒數十次 `onChange`，重建 controller 會閃）。
    func setPanel(_ model: PanelModel) {
        guard model != lastModel else { return }
        let view = PanelView(model: model, onPick: panelOnPick, onReset: panelOnReset)
        if let hostingController {
            hostingController.rootView = view
        } else {
            let hc = NSHostingController(rootView: view)
            hc.sizingOptions = [.preferredContentSize]
            hostingController = hc
            popover.contentViewController = hc
        }
        rootViewAssignments += 1
        lastModel = model
    }

    /// D-i：改色期間釘住 popover。解除有兩條路徑——`ColorPickerCoordinator.onEnd`（色板真的關掉）
    /// 與 `togglePopover`（無條件回 `.transient`，切到別的 app 再回來不會卡住）。
    func setPopoverPinned(_ pinned: Bool) {
        popover.behavior = pinned ? .semitransient : .transient
    }

    /// 改 internal（原為 `private`）：`controllerForwardsPanelCallbacks` 要能從測試
    /// 直接呼叫，驗證它是釘住 popover 的第二條解除路徑（spec §2 D-i）。
    @objc func togglePopover() {
        // 第二條解除路徑：不論開／關都先回 `.transient`。
        setPopoverPinned(false)
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // 開啟即 acknowledge（D2）—— 面板是唯一互動，用它當確認手勢
            onOpen?()
            // fail-soft（review-t01 I3）：`attachPopover()` 已經預掛過空 model，這裡是
            // 保底第二層——沒有內容就別呼叫 `NSPopover.show`（否則整個行程被 NSException 殺掉）。
            guard popover.contentViewController != nil else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    var isVisible: Bool { item.isVisible }

    func apply(_ appearance: IconAppearance, phase: Double) {
        drawing.update(appearance, phase: phase)
        item.button?.toolTip = Self.tooltip(for: appearance)
    }

    static func tooltip(for a: IconAppearance) -> String {
        // 第二個數字與 PanelViewModel.title 同定義（live − attention）——persona S1-1：hover 說「3 個在跑」、點開說「1 個在跑」。
        // live 可以 < attention（已結束未確認的 error 進尾巴、不算 live）——review-t0406 B2：沒 guard 會印「-1 個在跑」。
        if a.attentionCount > 0 {
            let running = a.liveCount - a.attentionCount
            return running > 0 ? "\(a.attentionCount) 個需要你 · \(running) 個在跑" : "\(a.attentionCount) 個需要你"
        }
        if a.liveCount > 0 { return "\(a.liveCount) 個 session 在跑" }
        return "沒有活著的 session"
    }
}
