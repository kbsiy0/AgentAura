// Sources/AgentAuraApp/AppDelegate.swift
import AppKit
import AuraCore
import AuraHookFile

/// Composition root。唯一的組裝點。
///
/// T08：接線分散到三個 extension 檔避免撞 200 行——`AppDelegate+PanelActions.swift`
/// （窮盡 switch）、`AppDelegate+Connect.swift`（connect／disconnect／uninstall／登入項目）、
/// `AppDelegate+Verification.swift`（reprobe／背景 exec 驗證／`onOpen`）。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// internal（不是 private）——`refreshPanel`／`wireActions`／`performSetReduceMotion`
    /// （`AppDelegate+PanelActions.swift`）都要讀寫它們，跨檔 extension 碰不到 `private`。
    var graph: PipelineGraph!
    var status: (any IconRendering)!
    var driver: AnimationDriver!
    // internal（不是 private）：T24 的 `performUninstall`（AppDelegate+Connect.swift）要停它。
    var livenessTimer: Timer?

    /// internal（不是 private）讓 smoke test 能直接觀測／驅動——與 `paletteStore`／
    /// `colorCoordinator`（Change 2）同一個理由。
    var paletteStore: PaletteStore!
    var colorCoordinator: ColorPickerCoordinator!
    var verificationStore: HookVerificationStore!
    var loginItem: (any LoginItemControlling)!

    var installState: InstallState = .notConnected
    var optionsExpanded = false
    var launchAtLogin: Bool?
    var externalTargetPath: String?
    var banner: PanelBanner?
    /// T12（B5）：使用者的「減少動態」偏好——與系統值取 OR（`AnimationDriver.setUserReduceMotion`
    /// 是唯一的合併點），不是獨立生效。internal 讓 `performSetReduceMotion` 能寫它。
    var userReduceMotion = false
    /// T16：燈條底板開關，預設 true——internal 理由同 `userReduceMotion`。
    var iconPlate = true
    /// T26（i18n）：D-2 預設英文；key／preference／load／perform 都在 +PanelActions.swift。
    var language: Language = .english
    /// T32：D-3 預設 `.ledStrip`（不驚動既有使用者）；key／preference／load／perform
    /// 都在 `AppDelegate+IconShape.swift`。
    var iconShape: IconShape = .ledStrip
    /// internal（不是 private）：`AppDelegate+PanelActions.swift` 的 `presentAbout` 要讀它。
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

    static let didConnectOnceKey = "AgentAuraDidConnectOnce"

    /// **`installer` 生產預設值就是真的 `~/.claude`**（`productionUsesRealInstaller` 斷言）。
    let installer: Installer
    /// internal（不是 private）：`AppDelegate+Connect.swift` 的 `performUninstall()` 要用它
    /// 算 `~/.agentaura`（`root` 就是 `.../.agentaura/sessions`），跨檔 extension 碰不到 `private`。
    let root: URL
    private let livenessInterval: TimeInterval
    let defaults: UserDefaults
    private let makeRenderer: @MainActor () -> any IconRendering
    private let makeLoginItem: @MainActor () -> any LoginItemControlling
    // 以下四個跨檔 extension（PanelActions）都要用，同 `status` 的理由改 internal。
    let openURL: @MainActor (URL) -> Void
    let showAboutPanel: @MainActor ([NSApplication.AboutPanelOptionKey: Any]) -> Void
    let terminator: any AppTerminating
    /// T29（i18n）：帶 `Language`——`wireActions()` 送出時傳 `self.language`。
    let confirmDisconnect: @MainActor (Language, @escaping () -> Void) -> Void
    /// A5（T11 commit3）／T24：`.replaceExternalMount`／`.uninstall` 各自的確認框——同
    /// `confirmDisconnect` 的注入縫（測試不真的彈 `NSAlert`，spec §6.4）。
    let confirmReplaceExternalMount: @MainActor (Language, @escaping () -> Void) -> Void
    let confirmUninstall: @MainActor (Language, @escaping () -> Void) -> Void
    /// T32：`.setIconShape` 觸發時開啟的造型選單——同 `confirmDisconnect` 的注入縫，
    /// 測試不真的彈 `NSMenu`（spec §6.4）。
    /// T34：多帶 `IconAppearance`／`showsPlate` 為了畫縮圖（挑造型要看得到造型）——
    /// 兩個值都從 composition root 現場取，不是 view 自己去猜。
    let presentIconShapeMenu: @MainActor (IconShape, Language, IconAppearance, Bool, @escaping (IconShape) -> Void) -> Void

    init(root: URL = SnapshotIO.defaultRoot,
         livenessInterval: TimeInterval = 5,
         defaults: UserDefaults = .standard,
         installer: Installer = .production(),
         makeLoginItem: @escaping @MainActor () -> any LoginItemControlling = {
             LoginItem(translocated: RunningBundle.isTranslocated(), inDownloads: RunningBundle.isInDownloads())
         },
         openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
         // B4：帶真實內容（版本＋專案網址＋授權，見 `AboutContent`）——此前是空的 standard panel。
         showAboutPanel: @escaping @MainActor ([NSApplication.AboutPanelOptionKey: Any]) -> Void = { options in
             NSApp.activate(ignoringOtherApps: true)
             NSApp.orderFrontStandardAboutPanel(options)
         },
         terminator: any AppTerminating = RealTerminator(),
         confirmDisconnect: @escaping @MainActor (Language, @escaping () -> Void) -> Void =
             { language, onConfirm in DisconnectConfirmation.present(language: language, onConfirm: onConfirm) },
         confirmReplaceExternalMount: @escaping @MainActor (Language, @escaping () -> Void) -> Void =
             { language, onConfirm in ReplaceMountConfirmation.present(language: language, onConfirm: onConfirm) },
         confirmUninstall: @escaping @MainActor (Language, @escaping () -> Void) -> Void =
             { language, onConfirm in UninstallConfirmation.present(language: language, onConfirm: onConfirm) },
         presentIconShapeMenu: @escaping @MainActor (IconShape, Language, IconAppearance, Bool, @escaping (IconShape) -> Void) -> Void =
             { current, language, appearance, showsPlate, onSelect in
                 IconShapeMenu.present(current: current, language: language,
                                       appearance: appearance, showsPlate: showsPlate, onSelect: onSelect) },
         makeRenderer: @escaping @MainActor () -> any IconRendering = { StatusItemController() }) {
        self.root = root
        self.livenessInterval = livenessInterval
        self.defaults = defaults
        self.installer = installer
        self.makeLoginItem = makeLoginItem
        self.openURL = openURL
        self.showAboutPanel = showAboutPanel
        self.terminator = terminator
        self.confirmDisconnect = confirmDisconnect
        self.confirmReplaceExternalMount = confirmReplaceExternalMount
        self.confirmUninstall = confirmUninstall
        self.presentIconShapeMenu = presentIconShapeMenu
        self.makeRenderer = makeRenderer
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = makeRenderer()
        paletteStore = PaletteStore(defaults: defaults)
        colorCoordinator = ColorPickerCoordinator()
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
        refreshPanel()
        runFirstRunSequenceIfNeeded()
        launchVerificationIfNeeded(observed: obs)

        // spec §3.5：每 5s 重驗 pid，抓「terminal 被強制關掉、SessionEnd 沒來」
        livenessTimer = Timer.scheduledTimer(withTimeInterval: livenessInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.graph.refreshLiveness() }
        }
    }

}
