/// 面板上所有可觸發動作的統一入口（D-j）。App 層只暴露一個
/// `onAction: (PanelAction) -> Void)`，`AppDelegate` 用窮盡 switch 消化 ——
/// 新增 case 忘了接線會變成編譯錯誤，而不是靜默沒反應。
public enum PanelAction: Equatable, Sendable {
    case pickColor(Activity)          // 既有，併入（Change 2）
    case resetColors                  // 既有，併入（Change 2）
    case toggleOptions
    case connect                      // 一鍵接上／重新接上
    case replaceExternalMount         // D-i：明確選擇「改指向 App 內建」
    case disconnect                   // 呼叫端負責確認對話框
    case setLaunchAtLogin(Bool)
    case recheckHook                  // R2：`verified == false` 時的退化出口，不讓畫面停在未驗證
    case openHelp
    case about
    case dismissBanner
    case quit
    /// B2（成熟 app 缺項）：Amphetamine 的 Feedback & Support 對應——開 GitHub issues。
    case reportIssue
    /// B5：R4 注意力預算的使用者控制（不是抄功能）。與系統值取 OR，見 `AnimationDriver`。
    case setReduceMotion(Bool)
    /// T16：燈條底板開關（`LEDStripView.showsPlate`）——修正 spec §4.1 算術錯誤後補的
    /// 使用者控制，預設 true（見 `AppDelegate.iconPlateKey`）。
    case setIconPlate(Bool)

    /// 窮盡 switch：新增 case 這裡編不過，逼你同時補 `PanelActionKind`。
    public var kind: PanelActionKind {
        switch self {
        case .pickColor: .pickColor
        case .resetColors: .resetColors
        case .toggleOptions: .toggleOptions
        case .connect: .connect
        case .replaceExternalMount: .replaceExternalMount
        case .disconnect: .disconnect
        case .setLaunchAtLogin: .setLaunchAtLogin
        case .recheckHook: .recheckHook
        case .openHelp: .openHelp
        case .about: .about
        case .dismissBanner: .dismissBanner
        case .quit: .quit
        case .reportIssue: .reportIssue
        case .setReduceMotion: .setReduceMotion
        case .setIconPlate: .setIconPlate
        }
    }
}

/// `PanelAction` 帶 associated value 不能 `CaseIterable`（實測編譯失敗）——
/// 這個平行型別供 gate 推導「每一種動作都要有人接線」。
public enum PanelActionKind: String, Sendable, CaseIterable {
    case pickColor, resetColors, toggleOptions, connect, replaceExternalMount, disconnect
    case setLaunchAtLogin, recheckHook, openHelp, about, dismissBanner, quit
    case reportIssue, setReduceMotion, setIconPlate
}

extension PanelAction {
    /// 每個 `Kind` 的**全部**代表值（N7：單一代表值時「開有接、關沒接」照樣全綠）。
    /// `setLaunchAtLogin → [true, false]`；`pickColor → Activity.customizable.map(pickColor)`
    /// （`customizable` 本身已從 `Activity.allCases` 推導）；其餘回單元素陣列。
    /// **動作總數由 `PanelActionKind.allCases.flatMap(samples)` 推導，這裡不寫數字**（R6）。
    public static func samples(_ kind: PanelActionKind) -> [PanelAction] {
        switch kind {
        case .pickColor: Activity.customizable.map(PanelAction.pickColor)
        case .resetColors: [.resetColors]
        case .toggleOptions: [.toggleOptions]
        case .connect: [.connect]
        case .replaceExternalMount: [.replaceExternalMount]
        case .disconnect: [.disconnect]
        case .setLaunchAtLogin: [.setLaunchAtLogin(true), .setLaunchAtLogin(false)]
        case .recheckHook: [.recheckHook]
        case .openHelp: [.openHelp]
        case .about: [.about]
        case .dismissBanner: [.dismissBanner]
        case .quit: [.quit]
        case .reportIssue: [.reportIssue]
        case .setReduceMotion: [.setReduceMotion(true), .setReduceMotion(false)]
        case .setIconPlate: [.setIconPlate(true), .setIconPlate(false)]
        }
    }
}
