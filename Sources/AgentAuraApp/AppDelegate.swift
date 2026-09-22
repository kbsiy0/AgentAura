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
    /// T10：Codex 依賴 ＋ 五個行程常數（型別定義、`reprobeCodex()`／`performConnectCodex()`
    /// 等接線都在 `AppDelegate+Codex.swift`——這裡只放這一個 stored property）。
    var codexRuntime: CodexRuntime
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
    /// T13a：純搬移 `applicationDidFinishLaunching` 之後，`AppDelegate+Lifecycle.swift`
    /// 也要讀它排 liveness timer——跨檔 extension 碰不到 `private`，同 `root` 的既有理由。
    let livenessInterval: TimeInterval
    let defaults: UserDefaults
    /// T13a：純搬移之後 `AppDelegate+Lifecycle.swift` 也要讀它們建 renderer／登入項目控制器，
    /// 跨檔 extension 碰不到 `private`，理由同 `livenessInterval`。
    let makeRenderer: @MainActor () -> any IconRendering
    let makeLoginItem: @MainActor () -> any LoginItemControlling
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
    /// T13j（S1-5，D-ac）：`.disconnectCodex` 的確認框——同 `confirmDisconnect` 的既有注入縫，
    /// 比照 Claude 側 `confirmDisconnect` 的形狀（第四個確認框）。
    let confirmDisconnectCodex: @MainActor (Language, @escaping () -> Void) -> Void
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
         // r1 review M4：無預設值，漏傳即編譯錯——同 `codexDependencies`（review M3）的既有
         // 理由，本 change 第三次同型。原本的預設值指向真 `NSAlert().runModal()`，
         // headless 測試若漏注入會永久卡住主執行緒（`disconnectClaimsSuccessButFileRemainsBecomesOccupied`
         // 已經撞過一次），只補撞到的那個呼叫點不是結構性防線——拿掉預設值讓編譯器
         // 帶路更新每一個 `AppDelegate(...)` 建構點。真的彈框只在 `main.swift` 明傳。
         confirmDisconnectCodex: @escaping @MainActor (Language, @escaping () -> Void) -> Void,
         presentIconShapeMenu: @escaping @MainActor (IconShape, Language, IconAppearance, Bool, @escaping (IconShape) -> Void) -> Void =
             { current, language, appearance, showsPlate, onSelect in
                 IconShapeMenu.present(current: current, language: language,
                                       appearance: appearance, showsPlate: showsPlate, onSelect: onSelect) },
         codexDependencies: CodexDependencies,   // review M3：無預設值，漏傳即編譯錯（曾害過一次寫真的 ~/.codex）
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
        self.confirmDisconnectCodex = confirmDisconnectCodex
        self.presentIconShapeMenu = presentIconShapeMenu
        self.makeRenderer = makeRenderer
        codexRuntime = CodexRuntime(dependencies: codexDependencies, store: CodexHookStore(defaults: defaults))
        super.init()
    }

}
