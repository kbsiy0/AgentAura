import Testing
import AppKit
@testable import AgentAuraApp
import AuraCore

/// spec `2026-09-09-panel-legend-palette-design.md` §6：`colorPanelConversion`、
/// `changeColorGuards`、`willCloseObservedOnce`。
///
/// `NSColorPanel.shared` 是行程級單例——每條測試自己 `detach()` + `orderOut(nil)`
/// 收尾，避免互相汙染（同一個 target 的其他測試也可能碰它）。
@MainActor
@Suite("ColorPickerCoordinator")
struct ColorPickerTests {

    func withCoordinator(_ body: (ColorPickerCoordinator) throws -> Void) rethrows {
        let coordinator = ColorPickerCoordinator()
        defer {
            coordinator.detach()
            NSColorPanel.shared.orderOut(nil)
        }
        try body(coordinator)
    }

    @Test("sRGB NSColor 轉換 ≤ 1/255；pattern image 回 nil；pick 後三個旗標與色都對")
    func colorPanelConversion() throws {
        try withCoordinator { coordinator in
            let nsColor = NSColor(srgbRed: 0.22, green: 0.55, blue: 0.81, alpha: 1)
            let converted = try #require(ColorPickerCoordinator.rgba(from: nsColor),
                "合法 sRGB NSColor 應該能被 rgba(from:) 轉換，實際回傳 nil")
            let expected = RGBA(r: 0.22, g: 0.55, b: 0.81, a: 1)
            #expect(converted.maxComponentDelta(expected) <= 1.0 / 255, """
                轉換誤差過大：實際 \(converted)，預期 \(expected)
                """)

            let pattern = NSColor(patternImage: NSImage(size: NSSize(width: 1, height: 1)))
            #expect(ColorPickerCoordinator.rgba(from: pattern) == nil, "pattern image 應轉換失敗回 nil")

            let current = RGBA(r: 0.44, g: 0.19, b: 0.77, a: 1)
            coordinator.pick(.waiting, current: current, anchor: nil, present: false)
            #expect(NSColorPanel.shared.showsAlpha == false, """
                pick 後 showsAlpha 應關閉，實際 \(NSColorPanel.shared.showsAlpha)
                """)
            #expect(NSColorPanel.shared.hidesOnDeactivate == false, """
                pick 後 hidesOnDeactivate 應為 false（否則切到別的 app 會走 orderOut、不發 willClose，釘住解不開），\
                實際 \(NSColorPanel.shared.hidesOnDeactivate)
                """)
            let panelColor = try #require(ColorPickerCoordinator.rgba(from: NSColorPanel.shared.color),
                "pick 後應該能從 panel.color 讀出合法顏色")
            #expect(panelColor.maxComponentDelta(current) <= 1.0 / 255, """
                pick 後 panel.color 應該 ≈ current \(current)，實際 \(panelColor)
                """)
        }
    }

    @Test("changeColor 的三關 guard：sender／activeActivity／sRGB 轉換（對抗式）")
    func changeColorGuards() throws {
        withCoordinator { coordinator in
            var calls: [(Activity, RGBA)] = []
            coordinator.onPick = { calls.append(($0, $1)) }

            // 實測（task-0203-report）：`NSColorPanel.color` 的 setter 在 target/action 已設時會**同步自動呼叫 action**
            // （與 isContinuous 無關）。所以 (d) 只靠「設色」觸發、不再顯式呼叫 changeColor，否則會算到兩次。
            // `pick()` 先清 target 再設色再掛 target，所以 pick 自己不會觸發。

            // (a) 沒 pick 過就直接呼叫 → activeActivity 為 nil 的 guard
            coordinator.changeColor(NSColorPanel.shared)
            #expect(calls.isEmpty, "(a) 沒 pick 過就 changeColor 不該呼叫 onPick，實際 \(calls.count) 次")

            // (c) sender 不是 NSColorPanel：要在 activeActivity 已設、色板色合法的狀態下測，
            // 否則會被 (a)／(b) 的 guard 巧合頂住（review 指出的遮蔽）。
            coordinator.pick(.error, current: RGBA(r: 0.1, g: 0.1, b: 0.1, a: 1), anchor: nil, present: false)
            coordinator.changeColor("not a panel")
            #expect(calls.isEmpty, "(c) sender 不是 NSColorPanel 時不該呼叫 onPick，實際 \(calls.count) 次")

            // (b) pick 後色轉不過 sRGB（pattern image）：設色會自動觸發一次 action，guard #3 必須擋下
            NSColorPanel.shared.color = NSColor(patternImage: NSImage(size: NSSize(width: 1, height: 1)))
            coordinator.changeColor(NSColorPanel.shared)
            #expect(calls.isEmpty, "(b) pattern image 轉換失敗時不該呼叫 onPick，實際 \(calls.count) 次")

            // (d) 正常流程：pick 後給合法 sRGB 色——setter 自動觸發 action 恰好一次
            coordinator.pick(.error, current: RGBA(r: 0.1, g: 0.1, b: 0.1, a: 1), anchor: nil, present: false)
            NSColorPanel.shared.color = NSColor(srgbRed: 0.3, green: 0.6, blue: 0.9, alpha: 1)
            #expect(calls.count == 1, "(d) 設合法色應觸發 onPick 恰好一次，實際 \(calls.count) 次")

            // (e) alpha 不變式（review-t0203 I1）：showsAlpha = false 不會正規化既有顏色的 alpha；rgba(from:) 必須強制 a = 1
            NSColorPanel.shared.color = NSColor(srgbRed: 0.2, green: 0.3, blue: 0.4, alpha: 0.5)
            #expect(calls.last?.1.a == 1, "(e) 半透明色進色板時 onPick 的 a 應被強制為 1，實際 \(String(describing: calls.last?.1.a))")
            let picked = calls.first?.1
            #expect(picked.map { $0.maxComponentDelta(RGBA(r: 0.3, g: 0.6, b: 0.9, a: 1)) <= 1.0 / 255 } == true,
                    "(d) onPick 的顏色應為 (0.3, 0.6, 0.9)，實際 \(String(describing: picked))")
            #expect(calls.first?.0 == .error, "(d) activity 應為 .error，實際 \(String(describing: calls.first?.0))")
        }
    }

    @Test("willClose 只監聽一次（連呼兩次 pick 不會重複註冊）；detach 後不再增加")
    func willCloseObservedOnce() throws {
        withCoordinator { coordinator in
            var endCalls = 0
            coordinator.onEnd = { endCalls += 1 }

            coordinator.pick(.error, current: RGBA(r: 0.1, g: 0.1, b: 0.1, a: 1), anchor: nil, present: false)
            coordinator.pick(.waiting, current: RGBA(r: 0.2, g: 0.2, b: 0.2, a: 1), anchor: nil, present: false)
            NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: NSColorPanel.shared)

            #expect(coordinator.endCount == 1, "連呼兩次 pick 後 post 一次 willClose，endCount 應為 1，實際 \(coordinator.endCount)")
            #expect(endCalls == 1, "onEnd 應該被呼叫一次，實際 \(endCalls)")

            coordinator.detach()
            NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: NSColorPanel.shared)
            #expect(coordinator.endCount == 1, "detach 之後再 post willClose，endCount 不該再增，實際 \(coordinator.endCount)")
        }
    }
}
