import Testing
import Foundation
@testable import AgentAuraApp
import AuraCore
import AuraHookFile

/// T35：`.pickIconShape` 組出來的 `IconAppearance` 必須併入使用者的「減少動態」偏好——
/// 這是 `IconShapeMenuPreview` 能不能正確不動的**前提**（`IconShapeMenuPreviewTests` 只驗
/// `targetFPS == 0` 時 `start()` 不排程，不驗這個 `targetFPS` 是不是真的照使用者偏好算出來的；
/// 兩條 gate 合起來才是完整的鏈路）。
///
/// 修之前：`AppDelegate+PanelActions.swift` 組 appearance 時完全沒傳 `reduceMotion`
/// ——T34 之前這不影響任何東西（選單縮圖固定用 `staticFullyOpaque`，動畫欄位直接被蓋掉），
/// T35 讓選單縮圖動畫改讀這個 appearance 的真實動畫曲線之後，這個缺口變成真的會讓
/// 使用者開了「減少動態」時選單預覽照樣動。
///
/// **前提用 `.waiting`，不是預設的 `.idle`**：`.idle` 的 `targetFPS` 恆為 0，不論
/// `reduceMotion` 是否併入都量不出差異（沒接的話這條 gate 會誤判為綠——已經實測驗證過，
/// 見下面 mutation 記錄）；`.waiting` 是 `AppearancePolicy` 真的會動的 activity，
/// 兩個方向（開／不開）才量得出差異。
@MainActor
@Suite("pickIconShape 的 appearance 併入減少動態偏好（T35）")
struct IconShapeMenuReduceMotionWiringTests {

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-iconshape-reducemotion-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 沿用 `PaletteWiringSmokeTests.writeSnapshot` 的既有慣例。
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

    /// 有界等待——沿用 `PaletteWiringSmokeTests.wait` 的既有慣例。
    func wait(upTo seconds: TimeInterval, until cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if cond() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// 建好一個已經 bootstrap 出 `.waiting` session 的 delegate，回傳拿得到的 appearance
    /// 陣列（每次 `.pickIconShape` 都會 append 一筆）與觸發用的 `onAction`。
    func makeWaitingDelegate() async throws
        -> (delegate: AppDelegate, spy: SpyRenderer, onAction: (PanelAction) -> Void, presented: () -> [IconAppearance]) {
        let root = try makeRoot()
        try writeSnapshot("rm-waiting", .waiting, to: root)
        let suite = "io.agentaura.tests.iconshapereducemotion.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let spy = SpyRenderer()
        let presented = Presented()

        let delegate = AppDelegate(
            root: root, livenessInterval: 0.05, defaults: defaults,
            confirmDisconnectCodex: { _, onConfirm in onConfirm() },
            presentIconShapeMenu: { _, _, appearance, _, onSelect in
                presented.appearances.append(appearance)
                onSelect(.ledStrip)
            },
            codexDependencies: .inert(),
            makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        await wait(upTo: 5) { spy.applied.contains { $0.activity == .waiting } }
        #expect(spy.applied.contains { $0.activity == .waiting }, "前提：先要 bootstrap 出一個 .waiting，否則這條 gate 量不出差異")
        let onAction = try #require(spy.onAction, "AppDelegate 沒有接 status.onAction")
        return (delegate, spy, onAction, { presented.appearances })
    }

    /// `presented.appearances` 需要跨閉包累積，包一個 class 當可變盒子（同 `Recorder` 的既有理由）。
    final class Presented {
        var appearances: [IconAppearance] = []
    }

    @Test("使用者開了「減少動態」→ 傳給選單的 appearance.targetFPS == 0（動畫預覽因此不會動）")
    func reduceMotionOnMakesMenuAppearanceStatic() async throws {
        let (delegate, _, onAction, presented) = try await makeWaitingDelegate()
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        delegate.performSetReduceMotion(true)
        onAction(.pickIconShape(.ledStrip))

        let appearance = try #require(presented().last, "presentIconShapeMenu 沒有被呼叫")
        #expect(appearance.targetFPS == 0, """
            使用者開了「減少動態」，但傳給選單的 appearance.targetFPS 是 \(appearance.targetFPS)
            （非 0）——IconShapeMenuPreview.start() 會照這個值排程，選單預覽會動起來，
            違反可及性承諾。
            """)
        #expect(appearance.animation == .none)
    }

    @Test("使用者沒開「減少動態」→ .waiting 這種本來會動的 activity 傳給選單的 appearance.targetFPS > 0")
    func reduceMotionOffKeepsMenuAppearanceAnimated() async throws {
        let (delegate, _, onAction, presented) = try await makeWaitingDelegate()
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        // **釘住系統那一半**：生產邏輯是「系統 OR 使用者」，而 `AnimationDriver` 在 init 時
        // 讀真的 `NSWorkspace` 系統設定。這條測試的主題是使用者偏好那一半，系統值只是前提。
        // CI runner（macOS 15）上系統「減少動態」是開的，於是這條在那裡必紅、在本機必綠——
        // 測試的結論不該取決於跑它的那台機器。
        delegate.driver.setSystemReduceMotion(false)

        onAction(.pickIconShape(.ledStrip))

        let appearance = try #require(presented().last, "presentIconShapeMenu 沒有被呼叫")
        #expect(appearance.targetFPS > 0, """
            .waiting 本來就該動（AppearancePolicy.motion(for: .waiting) fps 30），
            但傳給選單的 appearance.targetFPS 是 0——reduceMotion 併入的邏輯可能把它寫死成 true 了。
            """)
        #expect(appearance.animation != .none)
    }
}
