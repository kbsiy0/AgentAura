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

    /// T21：面板被外部點擊關掉時關色板用的注入點——比照 `openURL`／`confirmDisconnect`／
    /// `AppDelegate.showAboutPanel` 的既有慣例，測試灌 spy，不真的彈／關色板 UI。
    var closeColorPanel: () -> Void = { NSColorPanel.shared.close() }

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
    /// 色板位置只在**它還沒被顯示過**時由我們決定；一旦使用者自己搬過，
    /// `setFrameAutosaveName` 會讓 macOS 記住他的位置，我們不再蓋掉（T17）。
    static let frameAutosaveName = "AgentAuraColorPanel"
    /// 最後一次收到的錨點——`colorPanelAnchorIsWired` 用它證明 `AppDelegate` 真的把
    /// 選單列圖示的位置傳下來了（tested ≠ wired，Lessons #5）。
    private(set) var lastAnchor: CGRect?

    func pick(_ activity: Activity, current: RGBA, anchor: CGRect?, present: Bool = true) {
        lastAnchor = anchor
        let panel = NSColorPanel.shared
        if present, !panel.isVisible { place(panel, anchor: anchor) }
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

    /// 第一次出現時掛在選單列圖示下方（實機回報：沒存過位置時 macOS 放左下角，離色點很遠）。
    /// **已經有使用者上次留下的位置就尊重它——除非它擋住面板**（T20：實機二次回報，存檔位置
    /// 是 T17 時代留下的舊座標，永遠與現在的面板重疊；`setFrameUsingName` 每次都成功回 true，
    /// 讓一個壞位置永遠黏著，T18 的擺位規則因此永遠不會執行）。
    private func place(_ panel: NSColorPanel, anchor: CGRect?) {
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        let hasSavedFrame = panel.setFrameUsingName(Self.frameAutosaveName)
        let screen = anchor.flatMap { a in NSScreen.screens.first(where: { $0.frame.intersects(a) }) } ?? NSScreen.main
        guard let frame = Self.repositionedFrame(hasSavedFrame: hasSavedFrame, savedFrame: panel.frame,
                                                  panelSize: panel.frame.size, avoid: anchor,
                                                  screenVisibleFrame: screen?.visibleFrame)
        else { return }
        panel.setFrame(frame, display: false)
    }

    /// `place` 的可測部分：**不碰 `NSColorPanel.shared`**（碰它會在啟動時就把整個色板 UI
    /// 建出來——實測 +120 ms／+17 MB，review-t0203 I2）。剩下沒被測到的只有幾行膠水
    /// （讀 panel 尺寸／挑螢幕／`setFrame`），那一段要在真 app 上看。
    ///
    /// T20：把「該不該尊重存檔位置」與「第一次出現時的擺位規則」合併成一個決策——回 nil
    /// 表示維持現狀（不呼叫 `setFrame`），非 nil 就是該套用的新 frame。涵蓋三種情境：
    /// 存檔位置沒擋住面板（尊重它，回 nil）／存檔位置擋住面板（拋棄它，照規則重新擺位）／
    /// 第一次出現、沒有存檔位置（照規則擺位，行為與 T18 相同）。
    static func repositionedFrame(hasSavedFrame: Bool, savedFrame: CGRect, panelSize: CGSize,
                                  avoid: CGRect?, screenVisibleFrame: CGRect?) -> NSRect? {
        if hasSavedFrame, let avoid, !savedFrame.intersects(avoid) { return nil }
        guard let avoid, let screenVisibleFrame else { return nil }
        return plannedFrame(panelSize: panelSize, avoid: avoid, screenVisibleFrame: screenVisibleFrame)
    }

    static func plannedFrame(panelSize: CGSize, avoid: CGRect?, screenVisibleFrame v: CGRect) -> NSRect? {
        guard let avoid, panelSize.width > 0, panelSize.height > 0 else { return nil }
        let o = ColorPanelPlacement.origin(
            avoidMinX: avoid.minX, avoidMaxX: avoid.maxX, avoidMaxY: avoid.maxY,
            panelWidth: panelSize.width, panelHeight: panelSize.height,
            visibleMinX: v.minX, visibleMaxX: v.maxX, visibleMinY: v.minY, visibleMaxY: v.maxY)
        return NSRect(x: o.x, y: o.y, width: panelSize.width, height: panelSize.height)
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

    /// T21：面板關閉時呼叫——若正在改色（`activeActivity != nil`）就關掉色板，避免面板被
    /// 外部點擊關掉後系統色板變成孤兒視窗（面板已經看不到、色板還浮著，使用者得再手動關
    /// 一次）。**沒在改色時不得碰 `NSColorPanel.shared`**——碰它會把整個色板 UI 建出來
    /// （`init` 的 +120ms 註解），這是既有的刻意設計，`end()` 用同一顆 `activeActivity`
    /// guard 守住，不額外多摸一次色板單例。
    ///
    /// 收斂性：`closeColorPanel()` 在生產路徑是 `NSColorPanel.shared.close()`，會觸發
    /// `NSWindow.willCloseNotification` → 上面 `init` 裝的既有 handler → 清空
    /// `activeActivity`／`endCount += 1`／呼叫 `onEnd?()`（`AppDelegate` 接成
    /// `status.setPopoverPinned(false)`）。這條鏈**不會**再繞回 `end()` 本身——handler
    /// 裡沒有任何呼叫路徑會再次觸發面板的 `onClose`，遞迴到此為止。
    func end() {
        guard activeActivity != nil else { return }
        closeColorPanel()
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
