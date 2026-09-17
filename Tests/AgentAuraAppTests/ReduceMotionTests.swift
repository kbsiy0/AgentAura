import Testing
import Foundation
@testable import AgentAuraApp
import AuraCore

/// T12（B5）：「減少動態」不是抄 Amphetamine 的功能，是 R4 注意力預算的使用者控制——
/// 系統值與使用者偏好各自保存，`AnimationDriver.env.reduceMotion` 永遠是兩者的 OR。
/// `.waiting` 平常會動（`breathe`／30fps），reduceMotion 生效後變 `.none`／0fps，
/// 是這裡拿來當探針的活動（`AppearancePolicy.motion(for:)`，見 `IconAppearance.swift`）。
@MainActor
@Suite("B5：減少動態（系統值 OR 使用者偏好）", .serialized)
struct ReduceMotionTests {

    static let waitingIcon = IconState(activity: .waiting, counts: [.waiting: 1], liveCount: 1)

    // MARK: - AnimationDriver：使用者偏好那一半（系統值來自真的 NSWorkspace，見下面 persistence 測試改走 OptionsMenuModel 驗系統那一半）

    @Test("setUserReduceMotion(true)：waiting 的動畫被壓成靜態（targetFPS 0、animation .none）")
    func userPreferenceSuppressesAnimation() throws {
        var frames: [IconAppearance] = []
        let driver = AnimationDriver { appearance, _ in frames.append(appearance) }
        // **釘住系統那一半**：`AnimationDriver` 在 init 時從 `NSWorkspace` 讀真的系統設定，
        // 而生產邏輯是「系統 OR 使用者」。這條測試的主題是**使用者偏好**那一半，
        // 系統值是它的前提而不是它的受測對象——繼承機器狀態等於讓測試的結論取決於
        // 跑它的那台機器。CI runner（macOS 15）上系統「減少動態」是開的，
        // 於是前提斷言 `needsAnimation == true` 直接紅，而本機永遠看不到。
        driver.setSystemReduceMotion(false)
        driver.setIcon(Self.waitingIcon)
        let before = try #require(frames.last)
        #expect(before.needsAnimation == true, "前提：waiting 在使用者沒開減少動態時應該會動")

        driver.setUserReduceMotion(true)
        let after = try #require(frames.last)
        #expect(after.needsAnimation == false, "使用者開啟減少動態後，waiting 不該再動")
        #expect(after.animation == IconAnimation.none, "動畫型別應變成 .none，實際 \(after.animation)")
    }

    @Test("setUserReduceMotion(false)：關掉之後 waiting 恢復動畫（不是永久卡住）")
    func togglingBackOffRestoresAnimation() throws {
        var frames: [IconAppearance] = []
        let driver = AnimationDriver { appearance, _ in frames.append(appearance) }
        // **釘住系統那一半**：`AnimationDriver` 在 init 時從 `NSWorkspace` 讀真的系統設定，
        // 而生產邏輯是「系統 OR 使用者」。這條測試的主題是**使用者偏好**那一半，
        // 系統值是它的前提而不是它的受測對象——繼承機器狀態等於讓測試的結論取決於
        // 跑它的那台機器。CI runner（macOS 15）上系統「減少動態」是開的，
        // 於是前提斷言 `needsAnimation == true` 直接紅，而本機永遠看不到。
        driver.setSystemReduceMotion(false)
        driver.setIcon(Self.waitingIcon)
        driver.setUserReduceMotion(true)
        #expect(try #require(frames.last).needsAnimation == false, "前提：開啟後應該是靜態")

        driver.setUserReduceMotion(false)
        let after = try #require(frames.last)
        #expect(after.needsAnimation == true, "關掉使用者偏好後應該恢復動畫，實際 \(after)")
    }

    // MARK: - composition：AppDelegate 落盤與轉發

    func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-reducemotion-\(UUID().uuidString)/sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("composition：使用者偏好落盤持久化——下一個 AppDelegate（同一份 defaults）讀回同一個值")
    func userPreferencePersistsAcrossLaunches() throws {
        let suite = "io.agentaura.tests.reducemotion.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let spy1 = SpyRenderer()
        let delegate1 = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                    makeLoginItem: { FakeLoginItem() }, makeRenderer: { spy1 })
        delegate1.applicationDidFinishLaunching(Notification(name: .init("test")))
        #expect(delegate1.userReduceMotion == false, "前提：從沒設過，預設應為 false")
        let onAction1 = try #require(spy1.onAction)
        onAction1(.setReduceMotion(true))
        delegate1.applicationWillTerminate(Notification(name: .init("test")))

        let spy2 = SpyRenderer()
        let delegate2 = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                    makeLoginItem: { FakeLoginItem() }, makeRenderer: { spy2 })
        delegate2.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate2.applicationWillTerminate(Notification(name: .init("test"))) }
        #expect(delegate2.userReduceMotion == true, """
            第一個 AppDelegate 設過的偏好應該持久化，第二個（同一份 defaults）啟動時應該讀到 true
            """)
        #expect(spy2.panels.last?.userReduceMotion == true, "第二個 delegate 的面板 model 也應該反映落盤的偏好")
    }

    @Test("composition：setUserReduceMotion 真的轉發給 driver（不是只改旗標、動畫沒反應）")
    func compositionForwardsToDriver() throws {
        let suite = "io.agentaura.tests.reducemotion2.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let spy = SpyRenderer()
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   makeLoginItem: { FakeLoginItem() }, makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        var frames: [IconAppearance] = []
        delegate.driver = AnimationDriver { appearance, _ in frames.append(appearance) }
        delegate.driver.setSystemReduceMotion(false)   // 釘住系統那一半，理由同上
        delegate.driver.setIcon(Self.waitingIcon)
        #expect(frames.last?.needsAnimation == true, "前提：waiting 預設會動")

        let onAction = try #require(spy.onAction)
        onAction(.setReduceMotion(true))
        #expect(frames.last?.needsAnimation == false, """
            .setReduceMotion(true) 之後 driver 應該真的收到偏好、waiting 不該再動，
            實際 \(String(describing: frames.last))
            """)
    }

    /// E2（/simplify 波次2，reuse#10）：composition——系統值真的改變時，`driver.onEnvironmentChange`
    /// 要真的接到 `refreshPanel()`，不必使用者觸發任何其他動作面板就該反映新值。
    /// 真的系統值無法在測試裡控制，直接呼叫 `driver.setSystemReduceMotion`（internal，
    /// 理由見 `AnimationDriverGuardTests`）模擬「系統值真的變了」這個通知結果。
    @Test("composition：系統減少動態改變時，onEnvironmentChange 真的觸發 refreshPanel")
    func systemPreferenceChangeRefreshesPanel() throws {
        let suite = "io.agentaura.tests.reducemotion3.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let spy = SpyRenderer()
        let delegate = AppDelegate(root: try makeRoot(), livenessInterval: 0.05, defaults: defaults,
                                   makeLoginItem: { FakeLoginItem() }, makeRenderer: { spy })
        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        defer { delegate.applicationWillTerminate(Notification(name: .init("test"))) }

        let before = delegate.driver.systemReduceMotion
        #expect(spy.panels.last?.systemReduceMotion == before, "前提：面板應該反映目前的系統值")
        let panelCountBefore = spy.panels.count

        delegate.driver.setSystemReduceMotion(!before)

        #expect(spy.panels.count > panelCountBefore, """
            系統值真的改變後應該重畫過面板（setPanel 被再呼叫一次），實際次數沒變—— \
            代表 onEnvironmentChange 沒有真的接到 refreshPanel
            """)
        #expect(spy.panels.last?.systemReduceMotion == !before, """
            重畫後的面板應該反映新的系統值，實際 \(String(describing: spy.panels.last?.systemReduceMotion))
            """)
    }
}
