/// T29：「關於」面板的授權說明（`AboutContent.swift`）——README §授權目前寫
/// 「尚未決定（開源時確定）」，這裡照實搬，不瞎掰授權名字（同 `AboutContent` 既有理由：
/// 不能寫成 MIT／Apache 之類的授權名，`AboutContentTests.creditsContainsHonestLicenseText`
/// 守著這條）。
public enum L10nAbout: L10nCatalog, Sendable {
    case license

    public func text(_ language: Language) -> String {
        switch self {
        case .license:
            switch language {
            case .english: return "License: not yet decided (once open-sourced)"
            case .traditionalChinese: return "授權：尚未決定（開源時確定）"
            }
        }
    }
}
