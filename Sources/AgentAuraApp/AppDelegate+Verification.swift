// Sources/AgentAuraApp/AppDelegate+Verification.swift
import Foundation
import AuraCore
import AuraHookFile

/// T08：`reprobe()`／背景 exec 驗證／`onOpen` 的重新整理。**呼叫順序是強制的**
/// （T01 必辦④）：`installer.probe()` → `verificationStore.verification(for:)` →
/// `InstallState.from(_:verification:)`——只有這裡算一次，其餘處一律讀 `installState`。
extension AppDelegate {
    /// 便宜的那一半（不 exec，≈17µs）：磁碟現況 ＋ 憑證比對 → `installState`／
    /// `externalTargetPath`／`launchAtLogin`。**不得**在這裡呼叫任何 exec 驗證
    /// （S2-A12：面板路徑一律不得 exec）。
    func reprobe() {
        _ = reprobeObserving()
    }

    /// E6（/simplify 波次2，eff#6）：回傳剛探測到的 `LinkObservation`，讓
    /// `applicationDidFinishLaunching` 的啟動路徑能把它轉給 `launchVerificationIfNeeded`，
    /// 不必在幾微秒內重新 probe 一次（三次連續 probe ≈139µs＋18 次多餘 syscall，全部
    /// 擋在第一顆燈亮起之前，而狀態不可能在這幾微秒內變了）。其餘呼叫端仍用 `reprobe()`。
    @discardableResult
    func reprobeObserving() -> LinkObservation {
        let obs = installer.probe()
        let verification = verificationStore.verification(for: obs.hookBinaryStamp)
        apply(obs: obs, verification: verification)
        return obs
    }

    /// 共用欄位賦值，供 `reprobe()` 與 `beginBackgroundVerification` 的完成處理共用——
    /// 後者**不能**透過 `verificationStore.verification(for:)` 反推剛剛寫入的值（見下方
    /// `beginBackgroundVerification` 的說明），必須直接傳入已知的 `Verification`。
    private func apply(obs: LinkObservation, verification: Verification) {
        installState = InstallState.from(obs, verification: verification)
        // 波次2接線：`InstallState.owner`（B4，AuraCore）取代 app 層自己重寫的窮盡 switch——
        // 那份 switch 住在另一個 module，`InstallState` 的窮盡 gate（`affordanceMatchesTable` 等）
        // 看不到它，新增 case 或 `connected` payload 改形狀時可能漏改也不會變紅。
        externalTargetPath = installState.owner == .external ? obs.displayTargetPath : nil
        launchAtLogin = (loginItem?.isSupported == true) ? loginItem?.isEnabled : nil
    }

    /// `onOpen`（§4.4）：**只准 probe ＋ setPanel，一次都不得 acknowledge**（CLAUDE.md
    /// invariant；`PanelHostingTests.acknowledgeFiresOnCloseNotOpen` 是它的回歸 gate）。
    func handleOnOpen() {
        reprobe()
        reprobeCodex()   // D-t 時機②（CX24⑤）。
        refreshPanel()
    }

    /// 啟動後（N1）：`verification != .verified` 才跑；`recheckHook`（R2 的退化出口）
    /// 無條件跑，見 `AppDelegate+PanelActions.swift`。E6：`observed` 非 nil 時複用
    /// 呼叫端已經算好的 obs，不重新 probe；`.recheckHook` 傳 nil，那裡重新 probe 是對的
    /// （使用者明確要求重驗，狀態可能真的變了）。
    func launchVerificationIfNeeded(observed obs: LinkObservation? = nil) {
        let obs = obs ?? installer.probe()
        let verification = verificationStore.verification(for: obs.hookBinaryStamp)
        guard verification != .verified else { return }
        beginBackgroundVerification(observed: obs)
    }

    /// 合流 guard 住在 `verificationStore`（T01 必辦⑤）——已經有一個在跑就跳過。
    ///
    /// **不用 `Task.detached`**：`reverifyCurrentMount()` 內部是同步阻塞的 `usleep` 有界
    /// 等待（最長 `verificationTimeout` 秒）——`DispatchQueue.global()`（GCD 一般併發佇列）
    /// ＋ `withCheckedContinuation` 橋接回 async 是 Apple 文件建議的「呼叫同步阻塞 API」
    /// 寫法，執行緒不受 Swift 併發合作式池的限制。
    ///
    /// **完成後不得呼叫 `reprobe()`（實測踩過的 bug）**：`HookVerificationStore.beginVerification`
    /// 的結構是 `inFlight = Task { await work(); self?.inFlight = nil }`——`inFlight` 要等
    /// `work()` **完全返回之後**才清成 nil。若在 `work` 內部（也就是這裡）呼叫 `reprobe()`，
    /// 它讀到的 `verificationStore.verification(for:)` 這時 `inFlight` 依然非 nil，
    /// 一律搶答 `.inFlight`——`installState` 會被凍結成「檢查中…」，直到下一次有人主動
    /// 重新 probe 才會更新。修法：直接把剛算出來的 `Verification` 傳給
    /// `apply(obs:verification:)`，不透過會被 `inFlight` 攔住的 store 查詢。
    ///
    /// E6：`observed` 非 nil 時複用啟動路徑已經算好的 obs（見 `launchVerificationIfNeeded`）；
    /// `.recheckHook` 傳 nil 重新 probe。E9：`apply` 用的是 `reverifyCurrentMount()`
    /// **回傳的** observation（真的被 exec 驗過的那一份），不是這裡開頭那份——兩者原本
    /// 是不同時點的兩次 probe，「被驗的」與「被顯示的」在型別上現在保證是同一個值。
    func beginBackgroundVerification(observed obs: LinkObservation? = nil) {
        let obs = obs ?? installer.probe()
        guard let stamp = obs.hookBinaryStamp else { return }   // 沒有目標可驗，沒什麼好跑的
        let installerCopy = installer
        verificationStore.beginVerification { [weak self] in
            let (verifiedObs, result) = await withCheckedContinuation {
                (continuation: CheckedContinuation<(LinkObservation, Result<String, Error>), Never>) in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        let verified = try installerCopy.reverifyCurrentMount()
                        continuation.resume(returning: (verified.observation, .success(verified.stamp)))
                    } catch {
                        continuation.resume(returning: (obs, .failure(error)))
                    }
                }
            }
            guard let self else { return }
            let verification = self.verificationStore.record(result, fallbackStamp: stamp)
            self.apply(obs: verifiedObs, verification: verification)
            // S1-5（T13 收尾，PARTIAL 的殘餘一半）：驗證成功之後不清舊 banner，
            // 「接不上」的紅色錯誤條會在健康狀態已經翻回去之後還留在畫面上——
            // 這條路徑被自動啟動驗證（`launchVerificationIfNeeded`）與手動「再檢查一次」
            // （`AppDelegate+PanelActions.swift` 的 `.recheckHook`）共用，一次修兩邊。
            // 只清 `.error` kind：`.connected`／`.disconnected`／`.alreadyConnected`
            // 各自有自己的生命週期（`effectiveBanner`／使用者按 ✕），不該被這裡動到。
            if verification == .verified, self.banner?.kind == .error { self.banner = nil }
            self.refreshPanel()
        }
    }
}
