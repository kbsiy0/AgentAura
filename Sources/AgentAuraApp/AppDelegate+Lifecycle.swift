import AppKit
import AuraCore
import AuraHookFile

/// 首啟序列與終止收尾——拆檔理由同 `+Connect.swift`／`+PanelActions.swift`：
/// 避免 `AppDelegate.swift` 撞 200 行上限（T34 加了造型選單的縮圖參數之後撞到），
/// 不是抽象邊界。
extension AppDelegate {
    /// T13a（純搬移，零行為變更）：原本住在 `AppDelegate.swift`，為了替 T13j 的第四個
    /// 確認注入縫（`confirmDisconnectCodex`）在 200 行上限內騰出空間而搬過來——同
    /// `applicationWillTerminate` 已經住在這個檔案的既有先例，`NSApplicationDelegate`
    /// 的方法放在 extension 在本 repo 可行，不是理論推測。
    func applicationDidFinishLaunching(_ notification: Notification) {
        status = makeRenderer()
        paletteStore = PaletteStore(defaults: defaults)
        colorCoordinator = ColorPickerCoordinator()
        // 真圖示才准叫真色板；spy renderer 的測試行程裡 orderFront 只會落在開發者桌面上。
        colorCoordinator.presentsPanel = status.presentsSystemPanels
        verificationStore = HookVerificationStore(defaults: defaults)
        loginItem = makeLoginItem()
        driver = AnimationDriver { [weak self] appearance, phase in
            self?.status.apply(appearance, phase: phase)
        }
        // 同步區內（第一次 icon 交付之前）套上持久化的色——`onIconStateChange` 的
        // Task 一定落在後一個 turn，所以「同步區」比「在 graph.start() 之前」更準確
        // 的說法是「在下面這段回呼真正跑起來之前」（spec §4.3）。
        driver.setPalette(paletteStore.palette)
        // B5：同一段同步區內套上持久化的「減少動態」偏好，理由同上面那行（palette）。
        userReduceMotion = Self.reduceMotionPreference.load(from: defaults)
        driver.setUserReduceMotion(userReduceMotion)
        loadIconPlate()   // T16：同一段同步區內套上持久化的底板偏好，理由同上
        loadLanguage()    // T26：同一段同步區內套上持久化的語言偏好，理由同上（D-5(4)：預設英文）
        loadIconShape()   // T32：同上，理由同 loadIconPlate（D-3：預設 .ledStrip）

        paletteStore.onChange = { [weak self] in
            guard let self else { return }
            self.driver.setPalette(self.paletteStore.palette)
            self.refreshPanel()
        }
        // E2（/simplify 波次2，reuse#10）：系統「減少動態」真的改變時重畫面板——比照上面
        // paletteStore.onChange 的既有模式。原本系統設定改了只有 driver 自己重排動畫，
        // 沒有人呼叫 refreshPanel()，Options 那一列會停在舊值直到下一次事件。
        driver.onEnvironmentChange = { [weak self] in self?.refreshPanel() }
        colorCoordinator.onPick = { [weak self] activity, color in
            self?.applyColor(color, for: activity)
        }
        colorCoordinator.onEnd = { [weak self] in
            self?.status.setPopoverPinned(false)
        }
        wireActions()

        graph = PipelineGraph.production(root: root)
        // onIconStateChange 從 FSEvents 的背景 queue 上來，所以要 hop 回 main。
        graph.onIconStateChange = { icon in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.driver.setIcon(icon)
                self.driver.setIconVisible(self.status.isVisible)
                // E1（/simplify 波次2，eff#3）：把剛拿到的 icon 轉給 refreshPanel，不讓它
                // 自己再對 graph 上鎖重算一次——否則 driver 用的是這次鎖到的值、面板用的是
                // 下一次上鎖重算的值，兩者理論上可能不一致。
                self.refreshPanel(icon: icon)
            }
        }
        status.attachPopover()
        status.onClose = { [weak self] in
            guard let self else { return }
            // T21：面板關閉時若正在改色就一併關掉系統色板（避免孤兒色板留在畫面上）——
            // `end()` 自己的 guard 保證沒在改色時不會多做事，這裡不需要再判斷一次。
            self.colorCoordinator.end()
            self.graph.acknowledgeAll()
            self.refreshPanel()
        }
        status.onOpen = { [weak self] in self?.handleOnOpen() }
        graph.start()

        // §4.4：首啟順序強制——attachPopover→setPanel(真實狀態)→showPanel；obs 轉給下面（E6）。
        let obs = reprobeObserving()
        reprobeCodex()   // D-t 時機①：第一次 refreshPanel() 之前（CX24⑤）。
        refreshPanel()
        runFirstRunSequenceIfNeeded()
        launchVerificationIfNeeded(observed: obs)

        // spec §3.5：每 5s 重驗 pid，抓「terminal 被強制關掉、SessionEnd 沒來」
        livenessTimer = Timer.scheduledTimer(withTimeInterval: livenessInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.graph.refreshLiveness() }
        }
    }

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
