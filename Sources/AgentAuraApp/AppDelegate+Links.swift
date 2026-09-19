// Sources/AgentAuraApp/AppDelegate+Links.swift
import AppKit
import AuraCore

/// T07 預先搬移（原排在 T10 第一步，依賴方向寫反——`PanelAction` 加 case 在 T07，
/// 這批純搬移理當跟著提前，spec-writer 之後會回寫 plan）：`AppDelegate+PanelActions.swift`
/// 卡在 `Sources/` 200 行上限，把跟「開啟外部網址」相關、彼此無交集的 `reportIssue`／
/// `openHelp`／`helpResourceName`／`helpURL` 搬出來騰空間，給 T07 主 commit 的
/// `.connectCodex`／`.disconnectCodex`／`.copyCodexSnippet` stub 用。零行為變更：
/// 函式簽章與內容一字不改，只是換了一個檔案——`AppDelegate` 的 extension 成員本來就
/// 不分檔案（同 `HelpResourceNameTests` 呼叫 `AppDelegate.helpResourceName(for:)` 的既有
/// 慣例，不在乎它住在哪個檔）。
extension AppDelegate {
    /// B2：Amphetamine 的 Feedback & Support 對應——走既有注入的 `openURL`（測試斷言拿到
    /// 正確的 URL，不得真的開瀏覽器，spec §6.4）。
    func reportIssue() {
        openURL(ProjectLinks.newIssue)
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
