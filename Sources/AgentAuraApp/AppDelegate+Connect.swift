// Sources/AgentAuraApp/AppDelegate+Connect.swift
import Foundation
import AuraCore
import AuraHookFile

/// T08：`connect`／`replaceExternalMount`／`disconnect`／`setLaunchAtLogin` 的實作。
extension AppDelegate {
    /// `force == true` 送 `replaceExternalMount`（D-i：明確選擇改指向 App 內建），
    /// `false` 送一般 `connect`——`Installer` 的路由早退（`.none`）與否**必須在呼叫前**
    /// 用目前的 `installState` 判斷：`Installer.connect(...)` 對已接上狀態早退時只回傳
    /// 現有 stamp，不會重新 exec 驗證——這裡若照樣 `writeVerified`，會把一顆**從沒驗過**
    /// 的 stamp 標成已驗證（正是 N1／R2 在防的事）。`didConnectOnce` 只在真的走過完整
    /// 流程成功（無論早退或全新）時才寫——語意是「曾經接上過」，兩種成功都算。
    func performConnect(force: Bool) {
        // 波次2接線：`InstallState.isConnected`（B5，AuraCore）取代自己重寫的 IIFE
        // （與 `AppDelegate.runFirstRunSequenceIfNeeded` 是同一份逐字重複，見那裡的說明）。
        let wasAlreadyConnected = installState.isConnected
        // A5（T11 commit3）：換掉外部掛載前的目標——`reprobe()` 之後 owner 會變 `.thisApp`，
        // `externalTargetPath` 隨之被清成 nil，所以成功 banner 要說「換到哪」就必須在這裡先存起來。
        let priorExternalTarget = externalTargetPath
        let translocated = RunningBundle.isTranslocated()
        let inDownloads = RunningBundle.isInDownloads()
        do {
            let stamp = try (force
                ? installer.replaceExternalMount(translocated: translocated, inDownloads: inDownloads)
                : installer.connect(force: false, translocated: translocated, inDownloads: inDownloads))
            defaults.set(true, forKey: Self.didConnectOnceKey)
            // E7（/simplify 波次2，struct#C1）：三分支先前各自重複 `writeVerified(stamp)` ＋
            // `reprobe()`，「早退不得寫憑證」這條規則（`wasAlreadyConnected` 回的 stamp 從沒
            // 驗過，N1／R2）被稀釋成散在三處的隱含順序。改成一條 guard：規則本身只寫一次，
            // `reprobe()` 只出現一次（且仍在 banner 之前跑——`alreadyConnected` 要用的
            // `externalTargetPath` 得是 reprobe 之後的值）。
            if !wasAlreadyConnected { verificationStore.writeVerified(stamp) }
            reprobe()
            banner = wasAlreadyConnected ? .alreadyConnected(target: externalTargetPath)
                    : force ? .mountReplaced(from: priorExternalTarget)
                    : .connected()
        } catch let failure as InstallerFailure {
            handleConnectFailure(failure)
        } catch {
            banner = .error("接上失敗：\(error.localizedDescription)")
            reprobe()
        }
        refreshPanel()
    }

    /// E8（/simplify 波次2，alt#4／reuse#6）＋ B2（波次1）接線：文案改讀 AuraCore 的窮盡
    /// `PanelBanner.error(for:)`（漏一個 `InstallerFailure` case 就編譯錯），這裡只保留
    /// 「該不該寫哪個驗證憑證鍵」這一件事——與文案選擇分開，兩者不再擠在同一個 9-case switch裡。
    private func handleConnectFailure(_ failure: InstallerFailure) {
        switch failure {
        case .hookBlockedOrBroken(let stamp):
            verificationStore.writeBlocked(stamp)
        case .hookUnconfirmed(let stamp):
            verificationStore.writeUnconfirmed(stamp)
        case .mustMoveToApplications, .cannotConnect, .externalMountNeedsChoice,
             .bundleIncomplete, .writeTargetOccupied, .renameFailed, .verificationFailed:
            break   // 這幾種不寫任何驗證憑證鍵——文案仍在下面窮盡處理
        }
        banner = .error(for: failure)
        reprobe()
    }

    /// S1-A9：**不得**呼叫 `acknowledgeAll()`——只有 `onClose` 那一個呼叫點（G12）。
    func performDisconnect() {
        do {
            try installer.disconnect()
            reprobe()
            banner = .disconnected()
        } catch {
            banner = .error("移除掛載失敗：\(error.localizedDescription)")
            reprobe()
        }
        refreshPanel()
    }

    /// §4.2：設完**重讀實際值**——`.requiresApproval` 等失敗時開關要彈回去，
    /// `loginItem.isEnabled` 本就不快取，天然滿足。
    func performSetLaunchAtLogin(_ on: Bool) {
        do {
            try loginItem.set(on)
        } catch LoginItemError.requiresApproval {
            banner = .error("需要在系統設定 → 一般 → 登入項目 允許 AgentAura，之後才會真的生效。")
        } catch LoginItemError.mustMoveToApplications {
            // 波次2接線：與 `InstallerFailure.mustMoveToApplications` 共用同一句合併措辭
            // （B2，AuraCore）——先前這裡與那邊各自手搓一句，已經漂成兩種說法。
            banner = .error(InstallerFailure.mustMoveToApplicationsMessage)
        } catch {
            banner = .error("設定開機自動啟動失敗：\(error.localizedDescription)")
        }
        launchAtLogin = loginItem.isSupported ? loginItem.isEnabled : nil
        refreshPanel()
    }
}
