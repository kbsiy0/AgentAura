import Testing
import AppKit
@testable import AgentAuraApp
import AuraCore

/// E4（/simplify 波次2，eff#4／eff#12）：`AnimationDriver` 的 equality guard（不再每個
/// 事件都重排、把相位壓回 0）與觀察者移除（`stop()`）。E2（reuse#10）：`systemReduceMotion`
/// 曝光與 `onEnvironmentChange` 通知。
@MainActor
@Suite("AnimationDriver：equality guard／觀察者移除")
struct AnimationDriverGuardTests {
    static let waitingIcon = IconState(activity: .waiting, counts: [.waiting: 1], liveCount: 1)
    static let errorIcon = IconState(activity: .error, counts: [.error: 1], liveCount: 1)

    @Test("setIcon 相同值不重排；真的變化才重排")
    func setIconSkipsRescheduleWhenUnchanged() {
        var frameCount = 0
        let driver = AnimationDriver { _, _ in frameCount += 1 }
        driver.setIcon(Self.waitingIcon)
        #expect(frameCount == 1, "第一次真的變化應該重排一次")
        driver.setIcon(Self.waitingIcon)
        #expect(frameCount == 1, "相同 icon 再設一次不該重排——沒變化卻重排會把動畫相位壓回 0")
        driver.setIcon(Self.errorIcon)
        #expect(frameCount == 2, "真的變化仍要重排")
    }

    @Test("setIconVisible 相同值不重排（update 的 equality guard）")
    func setIconVisibleSkipsRescheduleWhenUnchanged() {
        var frameCount = 0
        let driver = AnimationDriver { _, _ in frameCount += 1 }
        driver.setIconVisible(true)   // DisplayEnvironment() 預設就是 true，沒有變化
        #expect(frameCount == 0, "沒有變化不該重排")
        driver.setIconVisible(false)
        #expect(frameCount == 1, "真的變化才重排")
        driver.setIconVisible(false)
        #expect(frameCount == 1, "相同值再設一次不該重排")
        driver.setIconVisible(true)
        #expect(frameCount == 2, "變回去也要重排")
    }

    /// E2：真的系統「減少動態」值在測試裡無法控制（讀真的 `NSWorkspace`），
    /// `setSystemReduceMotion` 因此改成 internal 讓這裡能直接驗證 guard／回呼／曝光值，
    /// 不必切換真實系統設定。
    @Test("setSystemReduceMotion：相同值不重排／不觸發 onEnvironmentChange；真的變化才觸發")
    func setSystemReduceMotionGuardsAndNotifies() {
        var frameCount = 0
        var environmentChangeCount = 0
        let driver = AnimationDriver { _, _ in frameCount += 1 }
        driver.onEnvironmentChange = { environmentChangeCount += 1 }
        let initial = driver.systemReduceMotion

        driver.setSystemReduceMotion(initial)   // 相同值
        #expect(frameCount == 0, "相同值不該重排")
        #expect(environmentChangeCount == 0, "相同值不該觸發 onEnvironmentChange")

        driver.setSystemReduceMotion(!initial)   // 真的變化
        #expect(driver.systemReduceMotion == !initial, "systemReduceMotion 應該真的更新")
        #expect(frameCount == 1, "真的變化應該重排一次")
        #expect(environmentChangeCount == 1, """
            系統值真的改變時應該通知 AppDelegate 重畫面板——原本系統設定改了只有這裡自己 \
            重排動畫，沒有人呼叫 refreshPanel()，Options 那一列會停在舊值
            """)

        driver.setSystemReduceMotion(!initial)   // 再設同一個值
        #expect(frameCount == 1, "相同值再設一次不該重排")
        #expect(environmentChangeCount == 1, "相同值再設一次不該再觸發一次 onEnvironmentChange")
    }

    /// E4（eff#12）：block-based observer 由 notification center 持有，`stop()` 之前
    /// 移除路徑不存在——用 `screensDidSleepNotification`（不依賴真的系統設定，`screenAsleep`
    /// 預設 `false`）驗證：註冊時通知真的能觸發 reschedule；`stop()` 之後同一個通知不該
    /// 再有效果。`queue: .main` 的 block 是非同步派工到 main run loop，`await Task.yield()`
    /// 讓它有機會真的執行。
    @Test("stop() 之後：screensDidSleepNotification 不再觸發 reschedule")
    func stopRemovesObservers() async {
        var frameCount = 0
        let driver = AnimationDriver { _, _ in frameCount += 1 }
        driver.setIcon(Self.waitingIcon)
        let baseline = frameCount

        let nc = NSWorkspace.shared.notificationCenter
        nc.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        for _ in 0..<50 where frameCount == baseline { await Task.yield() }
        #expect(frameCount == baseline + 1, "前提：註冊時 screensDidSleepNotification 應該真的觸發一次 reschedule")

        driver.stop()
        nc.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        for _ in 0..<10 { await Task.yield() }
        #expect(frameCount == baseline + 1, """
            stop() 之後同一組通知不該再觸發 reschedule，實際 frameCount \(frameCount)—— \
            代表 observer 沒有真的被移除
            """)
    }
}
