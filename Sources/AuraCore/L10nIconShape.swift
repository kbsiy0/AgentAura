/// T32：`IconShape` 的雙語顯示名稱——比照既有 domain enum 的切法（D-1），case 對應
/// `IconShape.allCases`（`IconShape.displayName(_:)` 逐一委派過來，窮盡 switch 互相對齊）。
public enum L10nIconShape: L10nCatalog, Sendable {
    case ledStrip
    case dot
    case ring
    case capsule
    case sparkle
    case halfCircle

    public func text(_ language: Language) -> String {
        switch self {
        case .ledStrip:
            switch language {
            case .english: return "LED strip"
            case .traditionalChinese: return "LED 燈條"
            }
        case .dot:
            switch language {
            case .english: return "Dot"
            case .traditionalChinese: return "圓點"
            }
        case .ring:
            switch language {
            case .english: return "Ring"
            case .traditionalChinese: return "圓環"
            }
        case .capsule:
            switch language {
            case .english: return "Capsule"
            case .traditionalChinese: return "藥丸"
            }
        case .sparkle:
            switch language {
            case .english: return "Sparkle"
            case .traditionalChinese: return "星芒"
            }
        case .halfCircle:
            switch language {
            case .english: return "Half circle"
            case .traditionalChinese: return "半圓"
            }
        }
    }
}
