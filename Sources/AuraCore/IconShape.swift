/// T32：選單列 icon 的可選造型（design doc `2026-09-15-icon-shapes-design.md` §2／§3）。
///
/// D-2：造型是純顯示選擇，刻意不含任何顏色／動畫欄位——`IconAppearance`／`AppearancePolicy`
/// 一行都不因為這個型別存在而改動（見 `IconAppearanceUnchangedByIconShapeTests`）。
/// **`rawValue` 是落盤格式。** T36 加過一個自繪的彩虹貓造型、2026-09-15 移除
/// （造型做不好看）；磁碟上可能留著 `"nyanCat"`／`"rainbowCat"` 兩個舊字面，降級規則住在
/// 組裝點（`AppDelegate.iconShapePreference` 的 `legacyAliases`），這個 enum 本身
/// 不需要也不該認得舊字面。
public enum IconShape: String, CaseIterable, Sendable, Equatable {
    case ledStrip
    case dot
    case ring
    case capsule
    case sparkle
    case halfCircle

    /// SF Symbol 名稱（D-1：內建造型用 SF Symbols，不自己畫）——`nil` 代表這個造型不是
    /// 靠 SF Symbol 畫（目前只有 `.ledStrip`，沿用既有 `LEDStripView`）。
    /// `AgentAuraApp` 端拿這個字串去建 `NSImage`——
    /// `AuraCore` 零 AppKit 依賴，不能在這裡直接碰 `NSImage`。
    public var systemSymbolName: String? {
        switch self {
        case .ledStrip: return nil
        case .dot: return "circle.fill"
        case .ring: return "circle"
        case .capsule: return "capsule.fill"
        case .sparkle: return "sparkle"
        case .halfCircle: return "circle.lefthalf.filled"
        }
    }

    /// 雙語顯示名稱——委派給 `L10nIconShape`（D-5(3)：中文字面只能住在 `L10n*.swift`，
    /// 這裡不得直接寫死任何一句翻譯）。窮盡 switch、無 default：新增 case 忘了補這裡
    /// 是編譯錯誤，不會漏翻（同 `L10nCatalog` 機制的地基）。
    public func displayName(_ language: Language) -> String {
        switch self {
        case .ledStrip: return L10nIconShape.ledStrip.text(language)
        case .dot: return L10nIconShape.dot.text(language)
        case .ring: return L10nIconShape.ring.text(language)
        case .capsule: return L10nIconShape.capsule.text(language)
        case .sparkle: return L10nIconShape.sparkle.text(language)
        case .halfCircle: return L10nIconShape.halfCircle.text(language)
        }
    }
}
