import Testing
import Foundation
import AppKit
@testable import AgentAuraApp
import AuraCore
import AuraHookFile

/// 記錄 `AppDelegate` 對選單列做了什麼。
///
/// spec §5.2 的第 2 項：「`StatusItemController` **真的**收到 `IconState` 更新
/// （spy 斷言呼叫確實發生，不是被 catch-all 吞掉）」。
@MainActor
final class SpyRenderer: IconRendering {
    private(set) var applied: [IconAppearance] = []
    private(set) var panels: [PanelModel] = []
    /// Change 2：每次 `setPopoverPinned` 呼叫的參數，依序記錄。
    private(set) var pinned: [Bool] = []
    private(set) var attachedPopover = false
    var isVisible = true
    var onClose: (() -> Void)?
    var onPickColor: ((Activity) -> Void)?
    var onResetColors: (() -> Void)?

    func apply(_ appearance: IconAppearance, phase: Double) { applied.append(appearance) }
    func attachPopover() { attachedPopover = true }
    func setPanel(_ model: PanelModel) { panels.append(model) }
    func setPopoverPinned(_ pinned: Bool) { self.pinned.append(pinned) }
}

@Suite("Composition root smoke（spec §5.2）", .serialized)
struct CompositionSmokeTests {

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-app-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func writeSnapshot(_ id: String, _ a: Activity, to root: URL) throws {
        try SnapshotIO.update(sessionID: id, root: root) { _ in
            var s = SessionSnapshot(sessionID: id)
            s.mainActivity = a
            s.hookEventName = "PermissionRequest"
            s.pid = getpid()
            s.pidStartedAt = SysctlLiveness().startTime(ofPID: getpid())
            s.writtenAt = Date()
            return s
        }
    }

    /// 有界等待 —— 直接 `while` 會在 mutation 下變成掛住而不是變紅。
    @MainActor
    func wait(upTo seconds: TimeInterval, until cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if cond() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// **這條擋的是「產品完全不動而測試全綠」。**
    ///
    /// 最終 review 實測：把 `applicationDidFinishLaunching` 裡的 `graph.start()`
    /// 與 liveness timer 整段註解掉，全套件 220/220 依然全綠 ——
    /// 因為 `AgentAuraApp` 那一層當時沒有任何測試。
    @MainActor
    @Test("啟動後，選單列真的收到 bootstrap 出來的 IconState")
    func launchDeliversIconStateToRenderer() async throws {
        let root = try makeRoot()
        try writeSnapshot("wait1", .waiting, to: root)

        let spy = SpyRenderer()
        let delegate = AppDelegate(root: root, livenessInterval: 0.05, makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        await wait(upTo: 5) { spy.applied.contains { $0.activity == .waiting } }
        #expect(spy.applied.contains { $0.activity == .waiting }, """
            選單列從來沒收到 .waiting。
            這代表 composition root 沒有接起來 —— bootstrap 沒跑、callback 沒裝、
            或 driver 沒把 IconState 交給 renderer。產品開起來會永遠什麼都不顯示。
            """)
        #expect(spy.attachedPopover, "面板沒有掛上 —— 點選單列不會有反應")
    }

    /// liveness timer 真的有在跑（spec §3.5：每 5s 重驗 pid）。
    @MainActor
    @Test("liveness timer 會週期性重驗，狀態檔消失後燈會熄")
    func livenessTimerActuallyFires() async throws {
        let root = try makeRoot()
        try writeSnapshot("wait2", .waiting, to: root)

        let spy = SpyRenderer()
        let delegate = AppDelegate(root: root, livenessInterval: 0.05, makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        await wait(upTo: 5) { spy.applied.contains { $0.activity == .waiting } }
        #expect(spy.applied.contains { $0.activity == .waiting }, "前提：先要亮起來")

        try SnapshotIO.delete(sessionID: "wait2", root: root)
        await wait(upTo: 5) { spy.applied.last?.activity == .idle }
        #expect(spy.applied.last?.activity == .idle, """
            狀態檔消失後燈沒有熄 —— liveness timer 沒有在跑。
            spec §3.5 要求每 5s 重驗 pid，那是「terminal 被強制關掉、SessionEnd 沒來」
            的唯一防線。
            """)
    }

    /// 接縫 gate（不是 S1-3 的回歸 gate——那是 `PanelHostingTests.acknowledgeFiresOnCloseNotOpen`，
    /// 對舊順序實跑為 RED）。這條守兩件事：(1) 已結束的 done 進得了面板 model（`isEnded` 沒被濾掉）；
    /// (2) composition root 真的把 `onClose` 接到 `acknowledgeAll`——少接這條尾巴永遠清不掉（mutation m4）。
    /// 第 (1) 段在修前也綠，是刻意的：它守的是另一個失效，不是這次的 bug（review-ack QA）。
    @MainActor
    @Test("已結束的 done 留在面板 model 直到 onClose；onClose 之後燈回 idle、檔案刪除、列消失")
    func endedRowSurvivesUntilClose() async throws {
        let root = try makeRoot()
        try SnapshotIO.update(sessionID: "ended1", root: root) { _ in
            var s = SessionSnapshot(sessionID: "ended1")
            s.mainActivity = .done; s.terminated = true; s.writtenAt = Date(); return s
        }
        let spy = SpyRenderer()
        let delegate = AppDelegate(root: root, livenessInterval: 0.05, makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        await wait(upTo: 5) { spy.panels.last?.rows.contains { $0.isEnded } == true }
        #expect(spy.panels.last?.rows.contains { $0.isEnded } == true, """
            已結束的 done 沒有進面板 model —— 尾巴（spec §2.4）不存在，整夜跑完的 session 早上看不到。
            """)

        let close = try #require(spy.onClose, "composition root 沒有接 onClose —— 關面板永遠不會 acknowledge，尾巴永不清")
        close()
        await wait(upTo: 5) {
            spy.panels.last?.rows.isEmpty == true && spy.applied.last?.activity == .idle
                && SnapshotIO.allSessionIDs(root: root).isEmpty
        }
        #expect(spy.panels.last?.rows.isEmpty == true, "關面板後那列應消失，實際 \(spy.panels.last?.rows.count ?? -1) 列")
        #expect(spy.applied.last?.activity == .idle, "關面板後燈應回 idle，實際 \(String(describing: spy.applied.last?.activity))")
        #expect(SnapshotIO.allSessionIDs(root: root).isEmpty, "已結束且已確認 → 狀態檔應刪除")
    }

    /// spec `2026-09-09-m4-icon-form-design.md` §4.3／§8.2：A/B 決定（`docs/2026-09-09-m4-ab-decision.md`
    /// 選 A2）後，開發期形態切換用的型別與 key 已刪，`StatusItemController` 直接建贏家。
    /// 這條測試的 tested≠wired 守門角色不變：實跑真 controller，斷言真的建出 `LEDStripView`，
    /// 不是斷言「型別存在」就收工。
    @MainActor
    @Test("StatusItemController 建出的 drawing 是贏家 LEDStripView")
    func statusItemBuildsTheWinner() throws {
        let controller = StatusItemController()
        defer { controller.removeFromStatusBar() }

        #expect(controller.drawing is LEDStripView, """
            StatusItemController 應建出 LEDStripView（A/B 已定案選 A2），實際 \(type(of: controller.drawing))
            """)
    }

    /// spec `2026-09-09-m4-icon-form-design.md` §6：`statusItemWidthFollowsRenderer`。
    ///
    /// **A/B 收斂後的誠實註記（review-t09 I-1）**：只剩一個 `IconDrawing` conformer、一個 `preferredWidth`，
    /// 「derived 而非 hardcoded」已不可觀測——把 `item.length`／frame 寫死成贏家的正確數字（50／42）這條仍綠
    /// （reviewer 實測）。它現在守的是「等於 42+8／4／42／thickness」，寫死成錯的數字仍會紅。
    /// 要恢復「跟著 renderer 走」的觀測性，需注入第二個 conformer——那與 R9／§4.3「評後刪」相反，不做。
    /// A/B 定案後只剩一種形態，迴圈收斂為單一案例；三條 frame 斷言不變。
    @MainActor
    @Test("status item 長度 = preferredWidth + 8，安裝 frame 為 x 4／width preferredWidth／height bar thickness")
    func statusItemWidthFollowsRenderer() throws {
        let controller = StatusItemController()
        defer { controller.removeFromStatusBar() }

        #expect(controller.statusItemLength == controller.drawing.preferredWidth + 8, """
            statusItemLength(\(controller.statusItemLength)) 應為 \
            drawing.preferredWidth(\(controller.drawing.preferredWidth)) + 8
            """)
        let frame = try #require(controller.drawing as? NSView).frame
        #expect(frame.width == controller.drawing.preferredWidth, "frame.width 應等於 preferredWidth，實際 \(frame.width)")
        #expect(frame.origin.x == 4, "frame.origin.x 應為 4，實際 \(frame.origin.x)")
        #expect(frame.height == NSStatusBar.system.thickness, "frame.height 應等於 bar thickness，實際 \(frame.height)")
    }

    /// review-t01-0203 I4（tested ≠ wired）：像素 gate 全部直接呼叫 `view.update`、
    /// `launchDeliversIconStateToRenderer` 用 SpyRenderer 取代整個 controller——刪掉
    /// `StatusItemController.apply` 裡的 `drawing.update(...)` 全套件仍綠，產品是一顆永不更新的 icon。
    /// 這條走真的 controller：apply(error) 之後離屏渲 `drawing`，LED 像素必須是 error 色。
    @MainActor
    @Test("StatusItemController.apply 真的把 appearance 交給 drawing（像素為證）")
    func applyReachesDrawing() throws {
        let controller = StatusItemController()
        defer { controller.removeFromStatusBar() }

        let error = IconState(activity: .error, counts: [.error: 1], liveCount: 1)
        controller.apply(AppearancePolicy.appearance(for: error, reduceMotion: true), phase: 0)

        let led = try #require(controller.drawing as? LEDStripView)
        let px = try (try OffscreenRender.render(led, over: .black)).pixel(at: led.ledRect(at: 3).center)
        let expected = OffscreenRender.expected(IconPalette.default.error, curveAlpha: 1, over: RGBA(r: 20.0/255, g: 20.0/255, b: 22.0/255, a: 1))
        #expect(px.maxComponentDelta(expected) <= 2.0 / 255, """
            apply(.error) 之後 LED 像素是 \(px)，不是 error 色 \(expected) —— controller 沒把 appearance 交給 drawing。
            """)
    }
}
