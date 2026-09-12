import Testing
import Foundation
import AppKit
@testable import AgentAuraApp
import AuraCore
import AuraHookFile

/// Change 2（panel-legend-palette）接線 gate。獨立成檔避免 `CompositionSmokeTests.swift`
/// 撞 300 行（spec §6）：`paletteChangeReachesIcon`、`pickerChainIsWired`、
/// `controllerForwardsPanelCallbacks`、`persistedColorAppliesOnFirstFrame`、
/// `legendAlwaysPresent`、`hostingControllerIsReused`。
@Suite("Palette 接線 smoke（Change 2）", .serialized)
struct PaletteWiringSmokeTests {

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

    /// 有界等待——直接 `while` 在 mutation 下會變成掛住而不是變紅。
    @MainActor
    func wait(upTo seconds: TimeInterval, until cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if cond() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// 每測一個獨立 UUID suite（不是固定名——這幾條 smoke 不需要跨測試共用 domain，
    /// 用固定名反而要互相搶 `.serialized`），回傳名字讓呼叫端能在 `defer` 清掉。
    func freshDefaults() throws -> (defaults: UserDefaults, suiteName: String) {
        let suite = "io.agentaura.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite), "建不出 suite \(suite)")
        return (defaults, suite)
    }

    // MARK: - paletteChangeReachesIcon

    @MainActor
    @Test("applyColor 同步反映到 icon 顏色與面板 model（legend／isDefaultPalette 一起）")
    func paletteChangeReachesIcon() async throws {
        let root = try makeRoot()
        try writeSnapshot("pal1", .waiting, to: root)

        let spy = SpyRenderer()
        let (defaults, suiteName) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let delegate = AppDelegate(root: root, livenessInterval: 0.05, defaults: defaults, makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        await wait(upTo: 5) { spy.applied.contains { $0.activity == .waiting } }
        #expect(spy.applied.contains { $0.activity == .waiting }, "前提：先要 bootstrap 出一個 .waiting")

        let wild = RGBA(r: 0.87, g: 0.12, b: 0.55, a: 1)
        delegate.applyColor(wild, for: .waiting)

        let lastAppearance = try #require(spy.applied.last, "applyColor 之後 spy 應至少收到過一次 apply")
        #expect(lastAppearance.color == wild, "applyColor 後 icon 顏色應立刻變成新色，實際 \(lastAppearance.color)")

        let lastPanel = try #require(spy.panels.last, "applyColor 之後 spy 應至少收到過一次 setPanel")
        #expect(lastPanel.palette[.waiting] == wild, "面板 model.palette[.waiting] 應立刻變成新色，實際 \(lastPanel.palette[.waiting])")
        let legendColor = lastPanel.legend.first { $0.activity == .waiting }?.color
        #expect(legendColor == wild, "圖例 .waiting 應反映新色，實際 \(String(describing: legendColor))")
        #expect(lastPanel.isDefaultPalette == false, "改過色之後 isDefaultPalette 應為 false")
    }

    // MARK: - pickerChainIsWired

    @MainActor
    @Test("面板點色點 → 系統色板 → 套用回 store，四段各自獨立失敗訊息")
    func pickerChainIsWired() throws {
        let spy = SpyRenderer()
        let (defaults, suiteName) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults, makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }
        // 行程級單例：不清會讓後面的測試收到這裡的 willClose／target（review-t01 I1）
        defer { delegate.colorCoordinator.detach(); NSColorPanel.shared.orderOut(nil) }

        // (1) status.onAction 應該被接上（AppDelegate → coordinator.pick 的入口）。
        #expect(spy.onAction != nil, "AppDelegate 應該把 status.onAction 接到 coordinator.pick —— 目前是 nil")

        // (2) 觸發它：NSColorPanel 應該變成 store 的顏色，且 popover 應被釘住。
        //     用 `?()` 而非 `!()`——onAction 若真是 nil，呼叫應是安全的無動作，不是 crash。
        spy.onAction?(.pickColor(.waiting))
        let panelColor = ColorPickerCoordinator.rgba(from: NSColorPanel.shared.color)
        #expect(panelColor == Optional(delegate.paletteStore.palette[.waiting]), """
            (2) 點圖例後系統色板顏色應變成 store.palette[.waiting]，\
            實際 panel=\(String(describing: panelColor)) store=\(delegate.paletteStore.palette[.waiting])
            """)
        #expect(spy.pinned.last == true, "(2) 點圖例後 spy 應收到 setPopoverPinned(true)，實際 \(spy.pinned)")

        // (3) 驅動 coordinator 真的產色：changeColor 應該把新色寫回 store。
        let wild = RGBA(r: 0.31, g: 0.72, b: 0.09, a: 1)
        NSColorPanel.shared.color = NSColor(rgba: wild)
        delegate.colorCoordinator.changeColor(NSColorPanel.shared)
        #expect(delegate.paletteStore.palette[.waiting] == wild, """
            (3) changeColor 後 store.palette[.waiting] 應套用新色 \(wild)，實際 \(delegate.paletteStore.palette[.waiting])
            """)

        // (4) 關色板應該解除釘住。
        let pinnedCountBefore = spy.pinned.count
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: NSColorPanel.shared)
        #expect(spy.pinned.count > pinnedCountBefore && spy.pinned.last == false, """
            (4) willClose 後 spy 應收到 setPopoverPinned(false)，實際 pinned=\(spy.pinned)
            """)
    }

    // MARK: - controllerForwardsPanelCallbacks

    @MainActor
    @Test("StatusItemController 把面板 callback 轉發給 onAction；popover 雙路徑解除 pinned")
    func controllerForwardsPanelCallbacks() throws {
        // T20：`setPopoverPinned(true)` 現在會裝滑鼠 dismiss monitor——注入假的
        // install／remove，測試不得裝真的全域 monitor（spec §6.4）。
        let controller = StatusItemController(dismissMonitor: PanelDismissMonitor(
            installGlobal: { _ in "g" as AnyObject }, installLocal: { _ in "l" as AnyObject }, remove: { _ in }))
        defer { controller.removeFromStatusBar() }
        controller.attachPopover()   // 會預掛空 model 的 hosting controller（review-t01 I3），togglePopover 因此安全；gate 在 PanelHostingTests
        #expect(controller.popoverBehavior == .transient, "attachPopover 後初始值應為 .transient，實際 \(controller.popoverBehavior)")

        var received: [PanelAction] = []
        controller.onAction = { received.append($0) }
        controller.panelOnAction(.pickColor(.error))
        #expect(received.last == .pickColor(.error), "panelOnAction 應把 pickColor(.error) 轉發到 onAction，實際 \(String(describing: received.last))")

        controller.panelOnAction(.resetColors)
        #expect(received.last == .resetColors, "panelOnAction 應把 resetColors 轉發到 onAction，實際 \(String(describing: received.last))")

        controller.setPopoverPinned(true)
        #expect(controller.popoverBehavior == .semitransient, "setPopoverPinned(true) 後應為 .semitransient，實際 \(controller.popoverBehavior)")
        controller.setPopoverPinned(false)
        #expect(controller.popoverBehavior == .transient, "setPopoverPinned(false) 後應回 .transient，實際 \(controller.popoverBehavior)")

        // 第二條解除路徑：togglePopover 不論開關都應該回 .transient。
        controller.setPopoverPinned(true)
        controller.togglePopover()
        #expect(controller.popoverBehavior == .transient, "togglePopover 是第二條解除路徑，之後應回 .transient，實際 \(controller.popoverBehavior)")
    }

    // MARK: - persistedColorAppliesOnFirstFrame

    @MainActor
    @Test("持久化的色在第一次交付 icon 時就生效")
    func persistedColorAppliesOnFirstFrame() async throws {
        let (defaults, suiteName) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let wild = RGBA(r: 112.0 / 255, g: 232.0 / 255, b: 5.0 / 255, a: 1)   // = #70e805，8-bit 精確（review-t01 B2）
        // 手寫 "#rrggbb"（不透過 `PaletteCodec.hex`——那條本身是 stub，回空字串），
        // 讓這條 fixture 在 T03 讀 defaults 真的接上時也還是合法值，不必回頭改。
        let wildHex = "#" + [wild.r, wild.g, wild.b].map { String(format: "%02x", Int(($0 * 255).rounded())) }.joined()
        defaults.set(wildHex, forKey: "AgentAuraColor.error")

        let root = try makeRoot()
        try writeSnapshot("persist1", .error, to: root)

        let spy = SpyRenderer()
        let delegate = AppDelegate(root: root, livenessInterval: 0.05, defaults: defaults, makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        await wait(upTo: 5) { spy.applied.contains { $0.activity == .error } }
        let firstErrorFrame = try #require(spy.applied.first { $0.activity == .error }, "應該收到過至少一次 .error 的 apply")
        #expect(firstErrorFrame.color == wild, """
            第一次交付 .error 就應該是持久化的顏色 \(wild)，實際 \(firstErrorFrame.color)
            """)
    }

    // MARK: - legendAlwaysPresent

    @MainActor
    @Test("legend 永遠是四項，不論 rows 空或非空")
    func legendAlwaysPresent() async throws {
        let root = try makeRoot()
        try writeSnapshot("legend1", .working, to: root)

        let spy = SpyRenderer()
        let (defaults, suiteName) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let delegate = AppDelegate(root: root, livenessInterval: 0.05, defaults: defaults, makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        await wait(upTo: 5) { spy.panels.last?.rows.isEmpty == false }
        let nonEmptyPanel = try #require(spy.panels.last, "啟動並 bootstrap 一個 session 後應收到 setPanel")
        #expect(nonEmptyPanel.rows.isEmpty == false, "前提：這一輪 rows 應非空")
        #expect(nonEmptyPanel.legend.count == 4, "rows 非空時 legend 仍應是四項，實際 \(nonEmptyPanel.legend.count)")
        #expect(nonEmptyPanel.legend.map(\.activity) == [.error, .waiting, .working, .done], """
            legend 順序應與 customizable 一致，實際 \(nonEmptyPanel.legend.map(\.activity))
            """)

        try SnapshotIO.delete(sessionID: "legend1", root: root)
        await wait(upTo: 5) { spy.panels.last?.rows.isEmpty == true }
        let emptyPanel = try #require(spy.panels.last, "刪除 session 後應再收到一次 setPanel")
        #expect(emptyPanel.rows.isEmpty, "前提：這一輪 rows 應為空")
        #expect(emptyPanel.legend.count == 4, "rows 空時 legend 仍應是四項，實際 \(emptyPanel.legend.count)")
        // spec §6：「每次」setPanel 都要四項，不只抽樣兩次（review-t01 Minor 5）
        #expect(spy.panels.allSatisfy { $0.legend.count == 4 }, "每一次 setPanel 的 legend 都應為四項；有 \(spy.panels.filter { $0.legend.count != 4 }.count) 次不是")
    }

    /// spec §6 `resetReachesIconAndDefaults`：唯一從 true 側見證 `isDefault` 的 gate，
    /// 也是 `status.onResetColors → resetColors()` 這一跳唯一的守衛（review-t01 B3）。
    @MainActor
    @Test("重設：icon 色回預設、面板 isDefaultPalette 為 true、四 key 皆清除")
    func resetReachesIconAndDefaults() async throws {
        let root = try makeRoot()
        try writeSnapshot("reset1", .waiting, to: root)
        let spy = SpyRenderer()
        let (defaults, suiteName) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let delegate = AppDelegate(root: root, livenessInterval: 0.05, defaults: defaults, makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }
        await wait(upTo: 5) { spy.applied.last?.activity == .waiting }

        let wild = RGBA(r: 20.0 / 255, g: 200.0 / 255, b: 40.0 / 255, a: 1)
        delegate.applyColor(wild, for: .waiting)
        #expect(spy.panels.last?.isDefaultPalette == false, "前提：改色後 isDefaultPalette 應為 false")

        let onAction = try #require(spy.onAction, "AppDelegate 沒有接 status.onAction")
        onAction(.resetColors)
        #expect(spy.applied.last?.color == IconPalette.default.waiting, "重設後 icon 應回預設 waiting 色，實際 \(String(describing: spy.applied.last?.color))")
        #expect(spy.panels.last?.isDefaultPalette == true, "重設後面板 isDefaultPalette 應為 true（唯一從 true 側見證 isDefault 的地方）")
        for a in Activity.allCases where a != .idle {
            #expect(defaults.object(forKey: "AgentAuraColor.\(a.rawValue)") == nil, "重設後 AgentAuraColor.\(a.rawValue) 應被移除")
        }
    }
}
