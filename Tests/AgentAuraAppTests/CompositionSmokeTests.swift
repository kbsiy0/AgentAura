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
    private(set) var panels: [(String, [PanelRow])] = []
    private(set) var attachedPopover = false
    var isVisible = true
    var onOpen: (() -> Void)?

    func apply(_ appearance: IconAppearance, phase: Double) { applied.append(appearance) }
    func attachPopover() { attachedPopover = true }
    func setPanel(title: String, rows: [PanelRow]) { panels.append((title, rows)) }
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
}
