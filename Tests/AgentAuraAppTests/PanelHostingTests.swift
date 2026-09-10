import Testing
import Foundation
import AppKit
@testable import AgentAuraApp
import AuraCore
import AuraHookFile

/// spec `2026-09-09-panel-legend-palette-design.md` §6：`hostingControllerIsReused`。
/// 從 `PaletteWiringSmokeTests` 拆出（該檔逼近 300 行；review-t01 B3）。
@MainActor
@Suite("面板 hosting controller 重用", .serialized)
struct PanelHostingTests {

    @Test("hosting controller 只建一次、之後重用並依內容縮放；rootViewAssignments 正確累加")
    func hostingControllerIsReused() throws {
        let controller = StatusItemController()
        defer { controller.removeFromStatusBar() }

        func session(_ id: String) -> SessionState {
            SessionState(id: id, projectName: id, projectPath: nil,
                        permissionMode: nil, effort: nil, model: nil,
                        activity: .working, mainActivity: .working, subActivity: nil,
                        currentTool: "Bash", subagentTool: nil, toolDurationMs: nil,
                        turnStartedAt: nil, subagents: [:], toolFailures: 0,
                        lastMessage: nil, errorType: nil, toolError: nil,
                        liveness: .alive(pid: 1), updatedAt: Date())
        }

        let icon = IconState(activity: .working, counts: [.working: 1], liveCount: 1)
        let m1 = PanelModel.make(icon: icon, sessions: [session("a")], palette: .default)
        let m3 = PanelModel.make(icon: icon, sessions: [session("a"), session("b"), session("c")], palette: .default)

        controller.setPanel(m1)
        let first = try #require(controller.hostingController, "第一次 setPanel 之後 hostingController 應該非 nil")
        #expect(controller.rootViewAssignments == 1, "第一次 setPanel 之後 rootViewAssignments 應為 1，實際 \(controller.rootViewAssignments)")
        let heightAfterM1 = first.preferredContentSize.height

        controller.setPanel(m3)
        let second = try #require(controller.hostingController, "第二次 setPanel 之後 hostingController 應該非 nil")
        #expect(first === second, "應該重用同一個 hostingController 實例")
        #expect(controller.rootViewAssignments == 2, "換內容應讓 rootViewAssignments +1，實際 \(controller.rootViewAssignments)")
        // 同一個實例：高度要在此刻**快照**，否則下面「變小」那句是拿當下值跟自己比（恆假）——T05 報告抓到的測試 bug。
        let heightAfterM3 = second.preferredContentSize.height
        #expect(heightAfterM3 > heightAfterM1, """
            3 列應比 1 列高，實際 \(heightAfterM3) vs \(heightAfterM1)
            """)

        controller.setPanel(m1)
        #expect(controller.rootViewAssignments == 3, "換回 1 列內容仍應 +1，實際 \(controller.rootViewAssignments)")
        let third = try #require(controller.hostingController, "第三次 setPanel 之後 hostingController 應該非 nil")
        #expect(third.preferredContentSize.height < heightAfterM3, "換回 1 列高度應變小，實際 \(third.preferredContentSize.height) vs \(heightAfterM3)")

        controller.setPanel(m1)
        #expect(controller.rootViewAssignments == 3, """
            PanelModel 相同時應該跳過重建，rootViewAssignments 不應再增，實際 \(controller.rootViewAssignments)
            """)
    }

    /// review-t01 I3 ＋ review-t0406 I2：`NSPopover.show` 在 contentViewController 為 nil 時丟 ObjC exception 殺整個行程。
    /// 防線有兩層（`attachPopover` 預掛空 model、`togglePopover` 的 fail-soft guard），這條 gate 守第一層並實跑 toggle。
    /// 離屏 `show` 靜默無效（`isShown` 恆 false），所以只驗「跑得完」與 behavior。
    @Test("attachPopover 之後 hosting controller 已存在，togglePopover 跑得完且解除釘住")
    func attachPopoverPreparesHosting() throws {
        let controller = StatusItemController()
        defer { controller.removeFromStatusBar() }
        controller.attachPopover()
        #expect(controller.hostingController != nil, "attachPopover 應先掛一個空 model 的 hosting controller，否則第一次點燈條會 NSException")
        controller.setPopoverPinned(true)
        controller.togglePopover()
        #expect(controller.popoverBehavior == .transient, "togglePopover 應無條件解除釘住")
    }

    /// S1-3（persona 讀碼推論，2026-09-10 使用者實測證實為 S0）：舊 `togglePopover` 先 `onOpen`→acknowledge
    /// 再 `show`，已結束的 done/error 列在面板出現前就被刪——尾巴（spec §2.4）形同不存在。
    /// 離屏 `show` 靜默無效（`isShown` 恆 false），所以三段分別驗：(a) 開的路徑不得呼叫 `onClose`；
    /// (b) 對**這個** popover 送 `didCloseNotification` 恰好呼叫一次；(c) 對別的 popover 送不得呼叫（object 過濾）。
    @Test("acknowledge 手勢是關面板：togglePopover 開時不呼叫 onClose，popover didClose 才呼叫一次")
    func acknowledgeFiresOnCloseNotOpen() {
        let controller = StatusItemController()
        defer { controller.removeFromStatusBar() }
        var closes = 0
        controller.onClose = { closes += 1 }
        controller.attachPopover()

        controller.togglePopover()
        #expect(closes == 0, "開面板不得 acknowledge——那會把已結束的列在面板出現前刪掉（S1-3），實際呼叫 \(closes) 次")

        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: NSPopover())
        #expect(closes == 0, "別的 popover 關掉不算，實際呼叫 \(closes) 次")

        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: controller.popover)
        #expect(closes == 1, "面板關閉應恰好呼叫一次 onClose，實際 \(closes) 次")
    }

    /// review-t0406 B2：tooltip 的「N 個在跑」曾用 live − attention 而無 guard；已結束未確認的 error 在尾巴裡、
    /// 不算 live → 「1 個需要你 · -1 個在跑」。與 `PanelViewModel.title` 同一套三元式。
    @Test("tooltip 永不出現負數，且與面板標題同定義", arguments: [
        (1, 0, "1 個需要你"), (1, 1, "1 個需要你"), (1, 3, "1 個需要你 · 2 個在跑"),
        (0, 2, "2 個 session 在跑"), (0, 0, "沒有活著的 session"),
    ])
    func tooltipNeverNegative(_ attention: Int, _ live: Int, _ expected: String) {
        let icon = IconState(activity: attention > 0 ? .error : (live > 0 ? .working : .idle),
                             counts: attention > 0 ? [.error: attention] : [:], liveCount: live)
        let appearance = AppearancePolicy.appearance(for: icon, reduceMotion: true)
        let text = StatusItemController.tooltip(for: appearance)
        #expect(text == expected, "attention=\(attention) live=\(live) → 應為「\(expected)」，實際「\(text)」")
        #expect(!text.contains("-"), "tooltip 不得出現負數：\(text)")
    }
}
