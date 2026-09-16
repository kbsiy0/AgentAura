// Sources/AgentAuraApp/StatusItemController.swift
import AppKit
import SwiftUI      // NSHostingController
import AuraCore

/// 擁有 `NSStatusItem`，把 `IconAppearance` 交給 `drawing` 畫。`drawing` 型別是
/// `any IconDrawing`，conformer 有兩個：`LEDStripView`（A2 定案於
/// `docs/2026-09-09-m4-ab-decision.md`）與 `SFSymbolIconView`（T32 起的可選造型），
/// 由 `makeDrawingView(for:)` 依 `IconShape` 決定——controller 不綁死 view 型別（spec §2）。
@MainActor
final class StatusItemController: IconRendering {
    /// `internal`（不是 `private`）：`StatusItemController+IconFrame.swift` 要讀它取螢幕座標。
    let item: NSStatusItem
    /// T32：`let` → `var`（跨檔 extension `setIconShape` 要能整個換掉 conformer）。
    var drawing: any IconDrawing
    /// B1：右鍵/左鍵判別的注入點（測試灌假事件型別，生產讀真的 `NSApp.currentEvent`）。
    /// `@MainActor` 的函式型別：預設值閉包本身不帶隔離標記會被推成 nonisolated，
    /// 讀 `NSApp`（main actor-isolated）就過不了型別檢查（同 `RealTerminator` 的理由）。
    private let currentEventType: @MainActor () -> NSEvent.EventType?
    /// B3：面板顯示期間的 ⌘Q 監聽（注入以避免測試裝真的全域 monitor，見 `QuitKeyMonitor`）。
    /// internal（不是 `private`）：`StatusItemController+Dismiss.swift` 的 `presentPopover` 要用它。
    let quitMonitor: QuitKeyMonitor
    /// T20／T37：**面板顯示期間**裝的滑鼠 monitor（`PanelDismissMonitor`，接線在
    /// `+Dismiss.swift` 的 `startDismissMonitorIfNeeded`）。T37 之前只在釘住期間裝，
    /// 平常靠 `.transient` 收面板，而那對 `LSUIElement` app 不可靠。internal 理由同 `quitMonitor`。
    let dismissMonitor: PanelDismissMonitor
    /// T32：底板偏好的快取——`setIconShape`（`+IconShape.swift`）換掉 `drawing` 時要用它
    /// 讓新 view 延續使用者原本的選擇，`IconDrawing` 只有 `setShowsPlate`（單向），沒有 getter。
    var showsPlate = true

    init(currentEventType: @escaping @MainActor () -> NSEvent.EventType? = { NSApp.currentEvent?.type },
         quitMonitor: QuitKeyMonitor = QuitKeyMonitor(),
         dismissMonitor: PanelDismissMonitor = PanelDismissMonitor(),
         iconShape: IconShape = .ledStrip) {
        self.currentEventType = currentEventType
        self.quitMonitor = quitMonitor
        self.dismissMonitor = dismissMonitor
        item = NSStatusBar.system.statusItem(withLength: 0)
        let view = Self.makeDrawingView(for: iconShape)
        drawing = view
        Self.mount(view, on: item)          // 與 `setIconShape` 共用同一份掛載程序（reuse#2）
        item.button?.toolTip = "AgentAura"
        panelOnAction = { [weak self] action in self?.onAction?(action) }
    }

    /// 測試讀取用（`statusItemWidthFollowsRenderer`）。
    var statusItemLength: CGFloat { item.length }

    /// 測試 teardown 用；生產 controller 活到 app 結束，不需要呼叫。
    /// 不用 `deinit`——nonisolated deinit 碰非 Sendable 的 `NSStatusItem` 在 Swift 6 編不過。
    func removeFromStatusBar() {
        if let didCloseToken { NotificationCenter.default.removeObserver(didCloseToken) }
        didCloseToken = nil     // 測試 teardown 後若再 attach 才能重新註冊（review-ack S2）
        quitMonitor.stopIfNeeded()   // 防禦性收尾：教學／測試提早 teardown 時別留下全域 monitor
        dismissMonitor.stopIfNeeded()   // 同上，面板釘住期間裝的滑鼠 monitor 一樣別留下
        NSStatusBar.system.removeStatusItem(item)
    }

    /// internal（原為 `private`）：`acknowledgeFiresOnCloseNotOpen` 要能對**這個** popover 送 `didCloseNotification`。
    let popover = NSPopover()
    /// 面板**關閉**時呼叫——這是 acknowledge 手勢（D2）。不是開啟：舊版在 `show` 之前 acknowledge，
    /// 已結束的 done/error 列在面板出現前就被移出 registry，尾巴（spec §2.4）形同不存在（S1-3，2026-09-10 實測證實）。
    var onClose: (() -> Void)?
    private var didCloseToken: NSObjectProtocol?
    var onAction: ((PanelAction) -> Void)?
    /// T08：使用者點燈條、popover 要顯示之前呼叫（在 `togglePopover` 的 `show` 分支裡，
    /// `show(relativeTo:...)` 之前）——`showPanel()`（首次啟動自動開）刻意不觸發它。
    var onOpen: (() -> Void)?
    /// B1：只在右鍵時呼叫，緊接在 `onOpen` 之前（見 `togglePopover`）。
    var onRightClick: (() -> Void)?

    /// `PanelView` 的 `onAction` 綁到這個閉包（`init` 設好，轉發到 `onAction`）——
    /// `controllerForwardsPanelCallbacks` 守這條轉發。
    var panelOnAction: (PanelAction) -> Void = { _ in }

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
        // B1：右鍵也要能觸發同一個 action（`togglePopover` 內用 `currentEventType()` 分流）。
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // 關面板才 acknowledge。用 `didClose` 不用 `willClose`——後者在淡出動畫中就把列抽掉，會閃。
        // `queue: nil`＝在 post 的那條執行緒同步跑（NSPopover 一律 main），gate 才能同步斷言；
        // `object: popover` 過濾掉別的 popover（色板等）。這個類別不是 NSObject 子類，走 delegate 得改繼承，不值。
        if didCloseToken == nil {
            didCloseToken = NotificationCenter.default.addObserver(
                forName: NSPopover.didCloseNotification, object: popover, queue: nil
            ) { [weak self] _ in
                // B3／T20：面板關閉務必移除 ⌘Q monitor 與滑鼠 dismiss monitor，不論是誰關的
                // （使用者點開別處／Esc／⌘Q 自己／我們自己的 dismiss monitor 觸發 performClose）。
                MainActor.assumeIsolated {
                    self?.onClose?()
                    self?.quitMonitor.stopIfNeeded()
                    self?.dismissMonitor.stopIfNeeded()
                }
            }
        }
        // review-t01 I3：先掛一個空 model，讓 `popover.contentViewController` 從一開始就非 nil——
        // `togglePopover` 在 `contentViewController == nil` 時呼叫 `NSPopover.show` 會丟
        // NSException 殺掉整個行程，不是「這次點擊沒反應」。
        // T06：這是掛載前的佔位 model，AppDelegate 首次 refreshPanel() 前的短暫瞬間；
        // 真實 install／version／banner 等狀態一律由 AppDelegate 傳入，這裡只填安全預設。
        setPanel(PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                 install: .notConnected, version: "", optionsExpanded: false,
                                 launchAtLogin: nil, externalTargetPath: nil, banner: nil,
                                 systemReduceMotion: false, userReduceMotion: false, iconPlate: true,
                                 iconShape: .ledStrip, language: .english))
    }

    /// 首次建 `NSHostingController` 並設 `sizingOptions = [.preferredContentSize]`
    /// （macOS 13+，讓 `preferredContentSize` 隨 `rootView` 自動同步且會縮回——手動賦值會凍住，
    /// review r3 I-b 實測）；之後只換 `rootView`。`model` 未變就跳過（D-j：`isContinuous` 拖曳
    /// 每秒數十次 `onChange`，重建 controller 會閃）。
    func setPanel(_ model: PanelModel) {
        // 語言先記下來再比對 model——`guard model != lastModel` 會在 model 沒變時提早返回，
        // 但那時語言本來就沒變，所以不會漏。放在 guard 之前只是讓意圖更明確。
        if language != model.language { language = model.language; updateTooltip() }
        guard model != lastModel else { return }
        let view = PanelView(model: model, onAction: panelOnAction)
        if let hostingController {
            hostingController.rootView = view
        } else {
            let hc = NSHostingController(rootView: view)
            hc.sizingOptions = [.preferredContentSize]
            // T15（V1 落地）：`NSHostingController.view` 預設不透明，會把 `NSPopover` 自己的
            // 原生材質蓋掉——`PanelView` 這邊已經把 SwiftUI 內容背景交回 `.clear`，這裡補
            // AppKit 端那一半。**離屏渲染證明不了**（沒有真 `NSWindow`，vibrancy 不會生效）；
            // 這條要在真 app 上肉眼確認（T15 commit message 已標記）。
            hc.view.wantsLayer = true
            hc.view.layer?.backgroundColor = .clear
            hostingController = hc
            popover.contentViewController = hc
        }
        rootViewAssignments += 1
        lastModel = model
    }

    // `setPopoverPinned` 搬到 `StatusItemController+Dismiss.swift`（T20，避免撞 200 行上限）。

    /// 改 internal（原為 `private`）：`controllerForwardsPanelCallbacks` 要能從測試
    /// 直接呼叫，驗證它是釘住 popover 的第二條解除路徑（spec §2 D-i）。
    @objc func togglePopover() {
        // 第二條解除路徑：不論開／關都先回 `.transient`。
        setPopoverPinned(false)
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // B1：右鍵直接展開 Options；footer 的「Options ⌄」主入口不受影響，左鍵完全不變。
            if currentEventType() == .rightMouseUp { onRightClick?() }
            // 這裡**不**acknowledge（acknowledge 在 didClose）：`onOpen` 在 show 之前呼叫
            // （只 probe＋setPanel），讓使用者點開時看到的是磁碟上的最新狀態，不是上次
            // refreshPanel 留下的舊 model。
            onOpen?()
            presentPopover(from: button)
        }
    }

    /// T08（§4.4）：首次啟動自動開面板專用的程式化顯示——**不**觸發 `onOpen`（呼叫端已經
    /// 在此之前用真實狀態 `setPanel` 過）。已經開著就不重複呼叫 `show`。
    func showPanel() {
        guard let button = item.button else { return }
        guard !popover.isShown else { return }
        presentPopover(from: button)
    }

    // `presentPopover` 搬到 `StatusItemController+Dismiss.swift`（T20，避免撞 200 行上限；
    // 改 internal 讓跨檔 extension 碰得到，同檔內其餘成員改 internal 的理由）。

    var isVisible: Bool { item.isVisible }

    // T11（S0-2）：tooltip 依賴兩個獨立輸入（動畫幀 vs 安裝狀態），各自存最後一次收到的值。
    var lastAppearance = AppearancePolicy.appearance(for: .empty)
    var installState: InstallState = .notConnected
    /// T28 接線：tooltip 也要跟著語言走。`setPanel` 是唯一的傳遞路徑——`PanelModel` 每次
    /// `refreshPanel()` 都帶著當下語言過來，同 `installState` 走 `setInstallState` 的理由
    /// （單一匯集點，不另外開一條會漂掉的平行路徑）。預設 `.english` 對齊 D-2。
    var language: Language = .english

    func apply(_ appearance: IconAppearance, phase: Double) {
        drawing.update(appearance, phase: phase)
        lastAppearance = appearance
        updateTooltip()
    }

    func setInstallState(_ state: InstallState) {
        installState = state
        updateTooltip()
    }

}
