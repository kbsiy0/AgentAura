/// B2（/simplify 波次1，alt#2）：`InstallerFailure` 的 9 種結果 → banner 文案，單一
/// 窮盡來源。漏一個 case 就編譯錯——app 層 `handleConnectFailure` 先前手搓了 11 次，
/// 其中 `mustMoveToApplications` 甚至已經漂成兩種措辭（見 `InstallerFailure
/// .mustMoveToApplicationsMessage` 的文件）。這裡是新的唯一 oracle；app 層改用它
/// 之後不會再有第二份手搓字面（消費端改動屬於 wave 2）。
extension PanelBanner {
    /// T27（i18n）：`language` **帶預設值 `.traditionalChinese`**——`AppDelegate+Connect.swift`
    /// （T28 清單內）是唯一生產呼叫點，帶預設值同 `PanelModel.swift` 那批 banner 工廠的理由。
    public static func error(for failure: InstallerFailure, language: Language) -> PanelBanner {
        .error(message(for: failure, language: language))
    }

    static func message(for failure: InstallerFailure, language: Language) -> String {
        switch failure {
        case .mustMoveToApplications:
            return InstallerFailure.mustMoveToApplicationsMessage(language)
        case .cannotConnect(let reason):
            // 與 `healthLabel` 共用同一個 oracle（§3.3 的表），不手搓第二份文案——
            // 原 app 層 `cannotConnectMessage` 的邏輯搬過來。
            guard let reason else { return InstallState.claudeNotFound.healthLabel(language) }
            return InstallState.broken(reason, owner: .unknown).healthLabel(language)
        case .externalMountNeedsChoice:
            return L10nPanelBanner.externalMountNeedsChoice.text(language)
        case .bundleIncomplete:
            return L10nPanelBanner.bundleIncomplete.text(language)
        case .writeTargetOccupied:
            return L10nPanelBanner.writeTargetOccupied.text(language)
        case .renameFailed(let code):
            return L10nPanelBanner.renameFailed(code: code, language: language)
        case .verificationFailed:
            return L10nPanelBanner.verificationFailed.text(language)
        case .hookBlockedOrBroken:
            // S1-1：與按下按鈕之前 `explanationDetail` 顯示的處方共用同一句常數。
            return InstallState.hookBlockedPrescription(language)
        case .hookUnconfirmed:
            return InstallState.hookUnconfirmedPrescription(language)
        }
    }
}
