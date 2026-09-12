// Sources/AgentAuraApp/AppDelegate+PanelActions.swift
import AppKit
import AuraCore

/// T08：`PanelAction` 的窮盡 switch（D-j）——新增 case 這裡編不過，逼你同時決定要不要接線。
/// 拆成獨立檔案避免 `AppDelegate.swift` 撞 200 行。
extension AppDelegate {
    func wireActions() {
        // B1：右鍵快速路徑——強制展開（不是 toggle），footer 的「Options ⌄」主入口
        // （`.toggleOptions` action）完全不受影響、行為不變。
        status.onRightClick = { [weak self] in
            guard let self else { return }
            self.optionsExpanded = true
            self.refreshPanel()
        }
        status.onAction = { [weak self] (action: PanelAction) in
            guard let self else { return }
            switch action {
            case .pickColor(let activity):
                self.status.setPopoverPinned(true)
                self.colorCoordinator.pick(activity, current: self.paletteStore.palette[activity],
                                           anchor: self.status.avoidScreenFrame)
            case .resetColors:
                self.resetColors()
            case .toggleOptions:
                self.optionsExpanded.toggle()
                self.refreshPanel()
            case .connect:
                self.performConnect(force: false)
            case .replaceExternalMount:
                // A5（T11 commit3）：換掉開發者掛載前先確認——同 .disconnect 的注入縫，
                // 只有使用者確認才真的呼叫 performConnect(force: true)。
                self.confirmReplaceExternalMount { [weak self] in self?.performConnect(force: true) }
            case .disconnect:
                // 確認對話框由注入的閉包負責（測試不真的彈 NSAlert，spec §6.4）；
                // 只有使用者確認才真的呼叫 Installer.disconnect()。
                self.confirmDisconnect { [weak self] in self?.performDisconnect() }
            case .setLaunchAtLogin(let on):
                self.performSetLaunchAtLogin(on)
            case .recheckHook:
                // R2 的退化出口：不管目前狀態，無條件跑一次（合流 guard 仍住在 store，
                // 已經有一個在跑就跳過，不會與啟動驗證重疊）。
                self.beginBackgroundVerification()
            case .openHelp:
                self.openHelp()
            case .about:
                self.showAboutPanel(AboutContent.options(version: self.appVersion))
            case .dismissBanner:
                self.banner = nil
                self.refreshPanel()
            case .quit:
                self.terminator.terminate()
            case .reportIssue:
                self.reportIssue()
            case .setReduceMotion(let on):
                self.performSetReduceMotion(on)
            case .setIconPlate(let on):
                self.performSetIconPlate(on)
            }
        }
    }

    /// E1（/simplify 波次2，eff#3）：`icon` 非 nil 時直接用（FSEvents 回呼已經鎖過一次
    /// 算好），不再對 `graph` 另外上鎖重算；其餘呼叫端（connect／disconnect／驗證完成／
    /// onOpen 等）傳 nil 照舊現場讀。E2：`systemReduceMotion` 讀 `driver`（唯一由通知
    /// 維護的即時值），不再自己問一次 `NSWorkspace`。
    func refreshPanel(icon: IconState? = nil) {
        let icon = icon ?? graph.iconState
        // 使用者偏好讀 `userReduceMotion`（唯一寫入點是 `performSetReduceMotion`）。
        let model = PanelModel.make(icon: icon, sessions: graph.visibleSessions, palette: paletteStore.palette,
                                    install: installState, version: appVersion, optionsExpanded: optionsExpanded,
                                    launchAtLogin: launchAtLogin, externalTargetPath: externalTargetPath, banner: banner,
                                    systemReduceMotion: driver.systemReduceMotion,
                                    userReduceMotion: userReduceMotion, iconPlate: iconPlate)
        status.setPanel(model)
        // T11（S0-2）：installState 唯一的傳遞路徑——tooltip 才能反映「還沒接上」而不是
        // 一律說「沒有活著的 session」。`refreshPanel()` 是每次 install 可能改變後都會呼叫的
        // 單一匯集點（connect／disconnect／驗證完成／onOpen reprobe 皆經過這裡）。
        status.setInstallState(installState)
    }

    /// T16：`UserDefaults` 鍵，走既有的 `defaults` 注入點（比照 `reduceMotionKey`）。
    static let iconPlateKey = "AgentAuraIconPlate"
    /// E12（/simplify 波次2，reuse#11）：兩個既有布林偏好（這個＋`reduceMotionPreference`）
    /// 比照 `PaletteStore` 收成 `BoolPreference` 搬運層——原本各寫一套 load/persist、
    /// 兩種讀法（`bool(forKey:)` vs `object(forKey:) as? Bool ?? true`），只因為預設值不同；
    /// 第三個偏好要加時不必再從兩種寫法裡任選一種。
    static let iconPlatePreference = BoolPreference(key: iconPlateKey, defaultValue: true)
    static let reduceMotionPreference = BoolPreference(key: reduceMotionKey, defaultValue: false)

    /// 啟動時讀回持久化值。
    func loadIconPlate() {
        iconPlate = Self.iconPlatePreference.load(from: defaults)
        status.setIconPlate(iconPlate)
    }

    /// 落盤、轉發給 `drawing`、重畫面板三件事綁在一起——同 `performSetReduceMotion` 的理由，
    /// 沒有第二個地方可以只做其中一件。
    func performSetIconPlate(_ on: Bool) {
        iconPlate = on
        Self.iconPlatePreference.persist(on, to: defaults)
        status.setIconPlate(on)
        refreshPanel()
    }

    /// B2：Amphetamine 的 Feedback & Support 對應——走既有注入的 `openURL`（測試斷言拿到
    /// 正確的 URL，不得真的開瀏覽器，spec §6.4）。
    func reportIssue() {
        openURL(ProjectLinks.newIssue)
    }

    /// B5：與系統值取 OR 的唯一寫入點——落盤、轉發給 `driver`、重畫面板三件事綁在一起，
    /// 沒有第二個地方可以繞過去只做其中一件（否則畫面與動畫實際行為會漂移）。
    func performSetReduceMotion(_ on: Bool) {
        userReduceMotion = on
        Self.reduceMotionPreference.persist(on, to: defaults)
        driver.setUserReduceMotion(on)
        refreshPanel()
    }

    /// `NSWorkspace` 的呼叫走注入的 `openURL` 閉包（測試斷言「真的拿那個 URL 去開」，
    /// 不是真的開瀏覽器）。`help.html` 的實際內容是 T09 的工作，這裡只負責接線；
    /// bundle 內找不到檔案（開發環境／尚未進 T09）時安全地什麼都不做。
    func openHelp() {
        guard let url = Self.helpURL() else { return }
        openURL(url)
    }

    /// E3（/simplify 波次2，struct#E2）：`??` 右邊原本只拼路徑、不驗存在性——只要
    /// `Bundle.main.resourceURL != nil`（app bundle 與 `swift test` 皆成立）就必定非 nil，
    /// 上面 `openHelp` 那句「找不到就什麼都不做」的 fail-soft guard 因此在生產路徑上恆真、
    /// 從未真的擋下任何東西（CLAUDE.md「八族空轉的守衛」）。補一次 `fileExists` 讓 guard
    /// 真的有牙齒——不改變其餘行為：找得到（多數情況）回同一個 URL，只是現在真的驗過。
    private static func helpURL() -> URL? {
        if let url = Bundle.main.url(forResource: "help", withExtension: "html") { return url }
        guard let fallback = Bundle.main.resourceURL?.appendingPathComponent("help.html"),
              FileManager.default.fileExists(atPath: fallback.path) else { return nil }
        return fallback
    }
}
