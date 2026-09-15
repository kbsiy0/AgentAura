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
                // 只有使用者確認才真的呼叫 performConnect(force: true)。T29：確認框文案要
                // 跟著目前顯示語言走，送出的當下傳 self.language（不是接線時就固定住）。
                self.confirmReplaceExternalMount(self.language) { [weak self] in self?.performConnect(force: true) }
            case .disconnect:
                // 確認對話框由注入的閉包負責（測試不真的彈 NSAlert，spec §6.4）；
                // 只有使用者確認才真的呼叫 Installer.disconnect()。
                self.confirmDisconnect(self.language) { [weak self] in self?.performDisconnect() }
            case .uninstall:
                // T24：同 .disconnect 的注入縫，只是確認框措辭更重（會列出五件事）。
                self.confirmUninstall(self.language) { [weak self] in self?.performUninstall() }
            case .setLaunchAtLogin(let on):
                self.performSetLaunchAtLogin(on)
            case .recheckHook:
                // R2 的退化出口：不管目前狀態，無條件跑一次（合流 guard 仍住在 store，
                // 已經有一個在跑就跳過，不會與啟動驗證重疊）。
                self.beginBackgroundVerification()
            case .openHelp:
                self.openHelp()
            case .about:
                self.showAboutPanel(AboutContent.options(version: self.appVersion, language: self.language))
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
            case .setLanguage(let language):
                self.performSetLanguage(language)
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
                                    userReduceMotion: userReduceMotion, iconPlate: iconPlate, language: language)
        status.setPanel(model)
        // T11（S0-2）：installState 唯一的傳遞路徑——tooltip 才能反映「還沒接上」而不是
        // 一律說「沒有活著的 session」。`refreshPanel()` 是每次 install 可能改變後都會呼叫的
        // 單一匯集點（connect／disconnect／驗證完成／onOpen reprobe 皆經過這裡）。
        status.setInstallState(installState)
    }

    /// T16：`UserDefaults` 鍵，走既有的 `defaults` 注入點（比照 `reduceMotionKey`）。
    static let iconPlateKey = "AgentAuraIconPlate"
    /// T12（B5）：`UserDefaults` 鍵——搬自 `AppDelegate.swift`（同 `iconPlateKey` 分檔理由）。
    static let reduceMotionKey = "AgentAuraReduceMotion"
    /// E12（/simplify 波次2，reuse#11）：兩個既有布林偏好（這個＋`reduceMotionPreference`）
    /// 比照 `PaletteStore` 收成 `BoolPreference` 搬運層——原本各寫一套 load/persist、
    /// 兩種讀法（`bool(forKey:)` vs `object(forKey:) as? Bool ?? true`），只因為預設值不同；
    /// 第三個偏好要加時不必再從兩種寫法裡任選一種。
    static let iconPlatePreference = BoolPreference(key: iconPlateKey, defaultValue: true)
    static let reduceMotionPreference = BoolPreference(key: reduceMotionKey, defaultValue: false)
    /// T26（i18n）：`UserDefaults` 鍵，走既有的 `defaults` 注入點（比照 `reduceMotionKey`）。
    static let languageKey = "AgentAuraLanguage"
    static let languagePreference = LanguagePreference(key: languageKey)

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

    /// 啟動時讀回持久化值（D-5(4)：未設定過時 `LanguagePreference.load` 回 `.english`）。
    func loadLanguage() {
        language = Self.languagePreference.load(from: defaults)
    }

    /// 落盤、重畫面板兩件事綁在一起——同 `performSetIconPlate` 的理由，沒有第二個地方
    /// 可以只做其中一件。D-3：這是 `language` 唯一的寫入點，不是全域狀態的隱式修改。
    func performSetLanguage(_ new: Language) {
        language = new
        Self.languagePreference.persist(new, to: defaults)
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
    /// 不是真的開瀏覽器）。`help.html` 的實際內容是 T09 的工作；T30（i18n）改成依
    /// `self.language` 選檔——bundle 內找不到對應語言的檔案時安全地什麼都不做。
    func openHelp() {
        guard let url = Self.helpURL(for: language) else { return }
        openURL(url)
    }

    /// T30（i18n）：檔名規則——`help-<Language.rawValue>.html`（`rawValue` 已被
    /// `LanguageTests.rawValuesArePinned` 釘死為 `"english"`／`"traditionalChinese"`）。
    /// 純函式、不摸 `Bundle`，`scripts/build-app.sh` 的 `Resources/help-*.html` glob
    /// 各自從同一條命名規則推導要複製／要找哪些檔，不手抄「有哪些語言」這份清單——
    /// 哪天 `Language` 真的加第三個 case，兩邊都不必改，只要多放一個對應檔名的資源檔。
    nonisolated static func helpResourceName(for language: Language) -> String {
        "help-\(language.rawValue)"
    }

    /// E3（/simplify 波次2，struct#E2）：`??` 右邊原本只拼路徑、不驗存在性——只要
    /// `Bundle.main.resourceURL != nil`（app bundle 與 `swift test` 皆成立）就必定非 nil，
    /// 上面 `openHelp` 那句「找不到就什麼都不做」的 fail-soft guard 因此在生產路徑上恆真、
    /// 從未真的擋下任何東西（CLAUDE.md「八族空轉的守衛」）。補一次 `fileExists` 讓 guard
    /// 真的有牙齒——不改變其餘行為：找得到（多數情況）回同一個 URL，只是現在真的驗過。
    private static func helpURL(for language: Language) -> URL? {
        let name = helpResourceName(for: language)
        if let url = Bundle.main.url(forResource: name, withExtension: "html") { return url }
        guard let fallback = Bundle.main.resourceURL?.appendingPathComponent("\(name).html"),
              FileManager.default.fileExists(atPath: fallback.path) else { return nil }
        return fallback
    }
}
