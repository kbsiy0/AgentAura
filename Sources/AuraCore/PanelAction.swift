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
    /// T24：D-1「完整移除」——比 `.disconnect` 更進一步（登入項目／狀態目錄／偏好設定／
    /// app 本身都清掉）。呼叫端同樣負責確認對話框（不是這裡）。
    case uninstall
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
    /// T26（i18n）：面板顯示語言——帶目標語言（比照 `pickColor(Activity)`，不是
    /// `setLaunchAtLogin` 那種布林 toggle：語言不是二元「開/關」語意，是選了哪一個）。
    case setLanguage(Language)
    /// T32：選單列 icon 造型——Options 列的觸發送出「目前選中的造型」（給選單建打勾用），
    /// AppDelegate 開啟造型選單（注入縫，見 `AppEnvironment.swift` 的 `IconShapeMenu`），
    /// 使用者真的選了新造型之後，`performSetIconShape` 直接落地，**不**再送第二次
    /// `.pickIconShape` 回這個 switch——同 `.pickColor(Activity)` 的既有形狀：action 帶的是
    /// 「開啟選什麼的脈絡」，不是「已經決定的新值」。
    ///
    /// **T33 後改名 `setIconShape` → `pickIconShape`**：原名會讓下一個讀的人以為
    /// 「送這個 action 就會把造型設成參數那個值」而誤用。對照組：
    /// `IconRendering.setIconShape(_:)` 那個 protocol 方法**是**真的 setter，名字不動。
    case pickIconShape(IconShape)
    /// T07（R-6／D-k）：一鍵接上／重新接上 Codex。**重用同一個 case 服務兩種文案**
    /// （`.notConnected` 的「接上 Codex」與 `.connectedStalePath` 的「重新接上 Codex」）——
    /// 同 `.connect` 對 Claude 側的既有形狀，不為「重新接上」另開第四個 case（D-k：
    /// 94 個呼叫點的 fan-out 因此不再長大）。`performConnectCodex()` 的路徑判定 guard
    /// （R-9）必須在任何 `disconnect` 之前 return，這個 case 本身不帶任何 payload。
    case connectCodex
    /// T07：拆掉 Codex 這邊的掛載——呼叫端負責確認對話框（同 `.disconnect` 的既有形狀）。
    case disconnectCodex
    /// T07（R-10／D-s）：把 `CodexHooksJSON.snippet(...)` 複製到剪貼簿。**進 `nonMenuKinds`**
    /// （不是 Options 選單列）——觸發處在面板卡片內的「複製」按鈕（`.occupiedByOther`／
    /// `.blockedByBundlePath(.unsupportedCharacter)` 兩態才會出現該按鈕），同
    /// `.replaceExternalMount` 需要 CTA 脈絡、不適合當一列裸選單項的既有理由。
    case copyCodexSnippet

    /// 窮盡 switch：新增 case 這裡編不過，逼你同時補 `PanelActionKind`。
    public var kind: PanelActionKind {
        switch self {
        case .pickColor: .pickColor
        case .resetColors: .resetColors
        case .toggleOptions: .toggleOptions
        case .connect: .connect
        case .replaceExternalMount: .replaceExternalMount
        case .disconnect: .disconnect
        case .uninstall: .uninstall
        case .setLaunchAtLogin: .setLaunchAtLogin
        case .recheckHook: .recheckHook
        case .openHelp: .openHelp
        case .about: .about
        case .dismissBanner: .dismissBanner
        case .quit: .quit
        case .reportIssue: .reportIssue
        case .setReduceMotion: .setReduceMotion
        case .setIconPlate: .setIconPlate
        case .setLanguage: .setLanguage
        case .pickIconShape: .pickIconShape
        case .connectCodex: .connectCodex
        case .disconnectCodex: .disconnectCodex
        case .copyCodexSnippet: .copyCodexSnippet
        }
    }
}

/// `PanelAction` 帶 associated value 不能 `CaseIterable`（實測編譯失敗）——
/// 這個平行型別供 gate 推導「每一種動作都要有人接線」。
public enum PanelActionKind: String, Sendable, CaseIterable {
    case pickColor, resetColors, toggleOptions, connect, replaceExternalMount, disconnect
    case uninstall
    case setLaunchAtLogin, recheckHook, openHelp, about, dismissBanner, quit
    case reportIssue, setReduceMotion, setIconPlate, setLanguage, pickIconShape
    case connectCodex, disconnectCodex, copyCodexSnippet
}

extension PanelAction {
    /// 每個 `Kind` 的**全部**代表值（N7：單一代表值時「開有接、關沒接」照樣全綠）。
    /// `setLaunchAtLogin → [true, false]`；`pickColor → Activity.customizable.map(pickColor)`
    /// （`customizable` 本身已從 `Activity.allCases` 推導）；其餘回單元素陣列。
    /// **動作總數由 `PanelActionKind.allCases.flatMap(samples)` 推導，這裡不寫數字**（R6）。
    /// 窮盡 `switch`，**不得有 `default`**——理由同 `CodexState.samples(_:)`：新增一個
    /// `PanelActionKind` case 忘了在這裡補齊，編譯器會擋下來；`default` 會讓這條定義域
    /// 推導鏈靜默失效（r3 m2）。
    public static func samples(_ kind: PanelActionKind) -> [PanelAction] {
        switch kind {
        case .pickColor: Activity.customizable.map(PanelAction.pickColor)
        case .resetColors: [.resetColors]
        case .toggleOptions: [.toggleOptions]
        case .connect: [.connect]
        case .replaceExternalMount: [.replaceExternalMount]
        case .disconnect: [.disconnect]
        case .uninstall: [.uninstall]
        case .setLaunchAtLogin: [.setLaunchAtLogin(true), .setLaunchAtLogin(false)]
        case .recheckHook: [.recheckHook]
        case .openHelp: [.openHelp]
        case .about: [.about]
        case .dismissBanner: [.dismissBanner]
        case .quit: [.quit]
        case .reportIssue: [.reportIssue]
        case .setReduceMotion: [.setReduceMotion(true), .setReduceMotion(false)]
        case .setIconPlate: [.setIconPlate(true), .setIconPlate(false)]
        case .setLanguage: Language.allCases.map(PanelAction.setLanguage)
        case .pickIconShape: IconShape.allCases.map(PanelAction.pickIconShape)
        case .connectCodex: [.connectCodex]
        case .disconnectCodex: [.disconnectCodex]
        case .copyCodexSnippet: [.copyCodexSnippet]
        }
    }
}
