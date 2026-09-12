/// B2（/simplify 波次1，alt#2）：`InstallerFailure` 的 9 種結果 → banner 文案，單一
/// 窮盡來源。漏一個 case 就編譯錯——app 層 `handleConnectFailure` 先前手搓了 11 次，
/// 其中 `mustMoveToApplications` 甚至已經漂成兩種措辭（見 `InstallerFailure
/// .mustMoveToApplicationsMessage` 的文件）。這裡是新的唯一 oracle；app 層改用它
/// 之後不會再有第二份手搓字面（消費端改動屬於 wave 2）。
extension PanelBanner {
    public static func error(for failure: InstallerFailure) -> PanelBanner {
        .error(message(for: failure))
    }

    static func message(for failure: InstallerFailure) -> String {
        switch failure {
        case .mustMoveToApplications:
            return InstallerFailure.mustMoveToApplicationsMessage
        case .cannotConnect(let reason):
            // 與 `healthLabel` 共用同一個 oracle（§3.3 的表），不手搓第二份文案——
            // 原 app 層 `cannotConnectMessage` 的邏輯搬過來。
            guard let reason else { return InstallState.claudeNotFound.healthLabel }
            return InstallState.broken(reason, owner: .unknown).healthLabel
        case .externalMountNeedsChoice:
            return "目前掛載指向別的地方，請選擇是否改指向這個 App。"
        case .bundleIncomplete:
            return "App 內建的 plugin 不完整，請重新下載安裝。"
        case .writeTargetOccupied:
            return "接上失敗：目標路徑被佔用。"
        case .renameFailed(let code):
            return "接上失敗（錯誤碼 \(code)）。"
        case .verificationFailed:
            return "接上後確認失敗，請再試一次。"
        case .hookBlockedOrBroken:
            // S1-1：與按下按鈕之前 `explanationDetail` 顯示的處方共用同一句常數。
            return InstallState.hookBlockedPrescription
        case .hookUnconfirmed:
            return InstallState.hookUnconfirmedPrescription
        }
    }
}
