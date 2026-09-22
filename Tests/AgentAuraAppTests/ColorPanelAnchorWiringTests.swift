import Testing
import Foundation
import AppKit
@testable import AgentAuraApp
import AuraCore
import AuraHookFile

/// T17（tested ≠ wired，Lessons #5）：`ColorPanelPlacement` 的規則可以 100% 正確，
/// 而 `AppDelegate` 忘了把選單列圖示的位置傳下去，色板照樣回到螢幕左下角。
/// 這條守的就是那一跳。
@MainActor
@Suite("色板錨點真的從選單列傳到 coordinator（T17）", .serialized)
struct ColorPanelAnchorWiringTests {

    @Test("點圖例色點 → coordinator 收到的錨點等於 renderer 回報的圖示位置")
    func colorPanelAnchorIsWired() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-anchor-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let spy = SpyRenderer()
        let defaults = try #require(UserDefaults(suiteName: "aura-anchor-\(UUID().uuidString)"))
        let delegate = AppDelegate(root: root, livenessInterval: 60, defaults: defaults,
                                   confirmDisconnectCodex: { _, onConfirm in onConfirm() }, codexDependencies: .inert(), makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        let action = try #require(spy.onAction, "composition root 沒有接 onAction")
        // present: false 不會真的開色板；我們要驗的是錨點有沒有被傳下來
        action(.pickColor(.waiting))

        #expect(delegate.colorCoordinator.lastAnchor == spy.avoidScreenFrame, """
            coordinator 收到的錨點是 \(String(describing: delegate.colorCoordinator.lastAnchor))，
            但 renderer 回報的圖示位置是 \(String(describing: spy.avoidScreenFrame))
            —— AppDelegate 沒有把它傳下去，色板會回到系統預設的左下角。
            """)
        #expect(delegate.colorCoordinator.lastAnchor != nil, "錨點不得是 nil")
    }

    /// `place` 的可測部分（`plannedFrame`）：錨點是 nil 或尺寸不合法時回 nil，
    /// 否則回一個掛在錨點下方、夾在可見範圍內的 frame。
    @Test("plannedFrame：有避開矩形才算，算出來不與面板重疊且不溢出")
    func plannedFrameAvoidsThePanel() {
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1055)
        let panel = CGRect(x: 1040, y: 415, width: 380, height: 640)   // 已顯示的面板
        #expect(ColorPickerCoordinator.plannedFrame(panelSize: CGSize(width: 225, height: 400),
                                                    avoid: nil, screenVisibleFrame: visible) == nil,
                "沒有避開矩形就不要硬放，交回系統預設")
        #expect(ColorPickerCoordinator.plannedFrame(panelSize: .zero, avoid: panel,
                                                    screenVisibleFrame: visible) == nil,
                "尺寸不合法（色板還沒 layout）時不要算")
        let frame = ColorPickerCoordinator.plannedFrame(panelSize: CGSize(width: 225, height: 400),
                                                        avoid: panel, screenVisibleFrame: visible) ?? .zero
        #expect(!frame.intersects(panel), "**使用者回報的 bug**：色板不得與面板重疊，實際 \(frame) vs \(panel)")
        #expect(visible.contains(frame), "必須完全落在可見範圍內，實際 \(frame)")
        #expect(abs(frame.maxY - panel.maxY) < 0.001, "上緣要與面板上緣對齊")
    }

    /// **使用者第二次回報的 bug（T20）**：`place` 尊重存檔位置的舊規則永遠 `return`，讓一個
    /// 曾經合法、現在因為面板換位置而重疊的存檔位置永遠黏著。這裡的 `overlappingSaved` 直接
    /// 取自使用者機器上讀出的鐵證：`"NSWindow Frame AgentAuraColorPanel" = "1138 832 250 298 0 0 1800 1130"`，
    /// 面板則掛在選單列圖示下方約 x 1101–1481、y 465–1105——兩者正好重疊。
    @Test("repositionedFrame：存檔位置擋住面板才重新擺位，沒擋住就尊重使用者搬過的位置")
    func repositionedFrameRespectsSavedPositionUnlessItOverlaps() {
        let visible = CGRect(x: 0, y: 0, width: 1800, height: 1130)
        let panelRect = CGRect(x: 1101, y: 465, width: 380, height: 640)   // 已顯示的面板
        let panelSize = CGSize(width: 250, height: 298)

        // 使用者實測的壞位置：與面板重疊——必須被拋棄、重新擺位到不重疊的地方。
        let overlappingSaved = CGRect(x: 1138, y: 832, width: 250, height: 298)
        let repositioned = ColorPickerCoordinator.repositionedFrame(
            hasSavedFrame: true, savedFrame: overlappingSaved, panelSize: panelSize,
            avoid: panelRect, screenVisibleFrame: visible)
        #expect(repositioned != nil, "**使用者回報的 bug**：存檔位置與面板重疊時必須重新擺位，不能維持現狀")
        if let repositioned {
            #expect(!repositioned.intersects(panelRect), "重新擺位後仍與面板重疊，實際 \(repositioned) vs \(panelRect)")
        }

        // 存檔位置沒有擋住面板——尊重使用者搬過的位置，不強制搬走（T17 的既有承諾）。
        let clearSaved = CGRect(x: 100, y: 100, width: 250, height: 298)
        let kept = ColorPickerCoordinator.repositionedFrame(
            hasSavedFrame: true, savedFrame: clearSaved, panelSize: panelSize,
            avoid: panelRect, screenVisibleFrame: visible)
        #expect(kept == nil, "存檔位置沒擋住面板時應維持現狀（回 nil），不該被覆寫，實際 \(String(describing: kept))")

        // 第一次出現（沒存過位置）：規則不變——照 plannedFrame 算，行為與 T18 相同。
        let firstTime = ColorPickerCoordinator.repositionedFrame(
            hasSavedFrame: false, savedFrame: .zero, panelSize: panelSize,
            avoid: panelRect, screenVisibleFrame: visible)
        #expect(firstTime != nil, "第一次出現、有錨點時應該照規則算出位置，不該回 nil")

        // 沒有錨點可用（anchor nil）：不管存檔位置擋不擋，都無從判斷，維持現狀。
        let noAnchor = ColorPickerCoordinator.repositionedFrame(
            hasSavedFrame: true, savedFrame: overlappingSaved, panelSize: panelSize,
            avoid: nil, screenVisibleFrame: visible)
        #expect(noAnchor == nil, "沒有錨點時無從判斷重疊，應維持現狀")
    }
}
