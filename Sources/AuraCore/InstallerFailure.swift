/// §4.1：`connect`／`replaceExternalMount`／exec 驗證失敗的明確結果。**憑證由 app 層寫**
/// （`HookVerificationStore`），所以這裡把「該寫哪個鍵」用帶 `stamp` 的 case 帶出來，
/// 而不是 `Installer` 自己碰 `UserDefaults`（R1）。成功路徑見 `connect(...)` 的回傳值
/// （驗證過的 `hookBinaryStamp`，供呼叫端寫 `AgentAuraHookVerified`）。
///
/// B2（/simplify 波次1，alt#2）：**搬進 `AuraCore`**（原住在 `AuraHookFile/Installer.swift`）——
/// payload 全是 AuraCore 型別（`InstallState.Reason?`／`Int32`／`String`），而它的文案
/// （`PanelBanner.error(for:)`，見 `PanelBanner+InstallerFailure.swift`）本就該窮盡推導、
/// 跟 `healthLabel`／prescription 常數同一層，不該只有 `Installer` 自己看得到這個型別。
///
/// C5（struct#9）：`.externalMountNeedsChoice`／`.verificationFailed` 原本各帶一份
/// `InstallState` payload——4 個建構點、0 個讀取點（app 層 `handleConnectFailure` 的
/// `case .externalMountNeedsChoice:` / `case .verificationFailed:` 都沒 binding，
/// banner 文案走固定字串），拿掉；與 `Tests/.../FakeInstaller.swift` 自己宣告的平行
/// （無 payload）`InstallerError` 形狀一致。
public enum InstallerFailure: Error, Equatable {
    case mustMoveToApplications
    case cannotConnect(InstallState.Reason?)
    case externalMountNeedsChoice
    case bundleIncomplete
    case writeTargetOccupied
    case renameFailed(Int32)
    case verificationFailed
    /// 真的跑完了但**確實沒有產物**：quarantine SIGKILL／arch 不符／複製損壞。
    /// 呼叫端寫 `AgentAuraHookBlocked = stamp`。
    case hookBlockedOrBroken(stamp: String)
    /// 逾時（機器睡眠等）或 spawn 本身丟錯：**無法確認**，不得反過來誤指控 macOS。
    /// 呼叫端寫 `AgentAuraHookUnconfirmed = stamp`（r6②／S2-11）。
    case hookUnconfirmed(stamp: String)

    /// B2：合併後的單一措辭——先前 `AppDelegate+Connect.swift` 對「App 需要先搬進
    /// 應用程式」這件事有兩種說法（`InstallerFailure.mustMoveToApplications` 用一種、
    /// `LoginItemError.mustMoveToApplications` 用另一種），已經漂移。這裡給通用措辭，
    /// 不綁單一動作（「接上」或「設定開機自動啟動」），兩處呼叫端之後都能共用（wave 2）。
    public static let mustMoveToApplicationsMessage =
        "請先把 AgentAura 搬進「應用程式」資料夾（或搬出 Downloads）再繼續。"
}
