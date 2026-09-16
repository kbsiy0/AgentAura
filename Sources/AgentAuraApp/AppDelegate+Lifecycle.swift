import AppKit
import AuraCore

/// 首啟序列與終止收尾——拆檔理由同 `+Connect.swift`／`+PanelActions.swift`：
/// 避免 `AppDelegate.swift` 撞 200 行上限（T34 加了造型選單的縮圖參數之後撞到），
/// 不是抽象邊界。
extension AppDelegate {
    /// §4.4：`!didConnectOnce && !connected` 才自動開面板；`didConnectOnce` 由
    /// `performConnect` 在真的接上成功時才寫（見 `AppDelegate+Connect.swift`），
    /// 不是這裡用當下狀態反推——旗標語意是「曾經走過接上流程成功」，不是巧合已連上。
    func runFirstRunSequenceIfNeeded() {
        // B5（波次2接線）：`InstallState.isConnected` 取代自己重寫的 IIFE（N9／S2-6）。
        guard !defaults.bool(forKey: Self.didConnectOnceKey), !installState.isConnected else { return }
        status.showPanel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        livenessTimer?.invalidate()
        graph?.stop()
        colorCoordinator?.detach()   // 收尾動作各自獨立（Lessons #8）；也讓每條建 AppDelegate 的 smoke 不留 observer
        driver?.stop()   // E4：同理，別留下 NSWorkspace 的三個死註冊
    }
}
