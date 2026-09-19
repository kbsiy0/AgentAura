/// D-5(2)(3) 兩條 gate 的推導依據：**所有** domain 字串表都要登記在這裡。
/// 新增一個 domain enum、忘了加到這裡——`L10nRegistrySourceScanTests`（來源掃描比對
/// `Sources/AuraCore/L10n*.swift` 的檔名 vs 這裡原始碼裡出現的型別名）會抓到。
public enum L10nRegistry {
    /// 每個 entry：這個鍵的「顯示名稱」（給錯誤訊息用，格式 `<Enum>.<case>`）＋
    /// 每種語言算出來的文字。**T27／T28 加新 domain enum 時，這裡也要跟著加一段**
    /// （同 `L10nCatalog` 說明——這份清單本身不是型別安全的，需要人手動同步，
    /// 靠 `L10nRegistrySourceScanTests` 頂住「忘了加」）。
    public static var allEntries: [(String, [Language: String])] {
        var out: [(String, [Language: String])] = []
        for c in L10nOptionsMenu.allCases {
            out.append(("L10nOptionsMenu.\(c)", byLanguage(c)))
        }
        for c in L10nPanel.allCases {
            out.append(("L10nPanel.\(c)", byLanguage(c)))
        }
        for c in L10nJargon.allCases {
            out.append(("L10nJargon.\(c)", byLanguage(c)))
        }
        for c in L10nSessionSummary.allCases {
            out.append(("L10nSessionSummary.\(c)", byLanguage(c)))
        }
        for c in L10nSessionRow.allCases {
            out.append(("L10nSessionRow.\(c)", byLanguage(c)))
        }
        for c in L10nInstallAffordance.allCases {
            out.append(("L10nInstallAffordance.\(c)", byLanguage(c)))
        }
        for c in L10nLegend.allCases {
            out.append(("L10nLegend.\(c)", byLanguage(c)))
        }
        for c in L10nPanelBanner.allCases {
            out.append(("L10nPanelBanner.\(c)", byLanguage(c)))
        }
        for c in L10nOptionsMenuRows.allCases {
            out.append(("L10nOptionsMenuRows.\(c)", byLanguage(c)))
        }
        for c in L10nAbout.allCases {
            out.append(("L10nAbout.\(c)", byLanguage(c)))
        }
        for c in L10nConfirmationAlerts.allCases {
            out.append(("L10nConfirmationAlerts.\(c)", byLanguage(c)))
        }
        for c in L10nUninstallConfirmation.allCases {
            out.append(("L10nUninstallConfirmation.\(c)", byLanguage(c)))
        }
        for c in L10nIconShape.allCases {
            out.append(("L10nIconShape.\(c)", byLanguage(c)))
        }
        for c in L10nCodex.allCases {
            out.append(("L10nCodex.\(c)", byLanguage(c)))
        }
        return out
    }

    private static func byLanguage<C: L10nCatalog>(_ c: C) -> [Language: String] {
        Dictionary(uniqueKeysWithValues: Language.allCases.map { ($0, c.text($0)) })
    }

    /// D-5(2) 的允許例外——兩語言字面刻意相同時（產品名、`⌘Q` 這類）才准列在這裡，
    /// **必須明列＋在這裡寫理由**，不得用「全部略過」。目前是空的：T26 的 3 個示範鍵
    /// 都刻意選了會隨語言變動的詞。
    public static let allowedSameAcrossLanguages: Set<String> = []
}
