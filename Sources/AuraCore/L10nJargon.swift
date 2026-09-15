/// T27：`Jargon` 的兩個查表（`effortMap`／`permissionModeMap`）搬進字串表——D-1 機制套用到
/// 「值本身就是一份查表」的場景：這裡的 `L10nCatalog.text(_:)` 不是給 UI 元件標題用，
/// 是給 `Jargon.effortMap(for:)`／`permissionModeMap(for:)` 組字典用的值。
///
/// **中文版才是真正的「翻譯」（把平台代碼字換成人話），英文版刻意保守**——`Jargon.swift`
/// 的既有理由（D-c）是「tool 名這種東西翻了反而對不起來」，同一個道理套用到這裡：
/// `auto`／`xhigh` 這類代碼字對英文讀者也不是天生易懂，但硬翻成長句一樣會對不起來，
/// 英文版只做輕度美化（`bypassPermissions` → "Auto-approve all"，不是逐字翻譯）。
public enum L10nJargon: L10nCatalog, Sendable {
    // MARK: - effort.level（四級）
    case effortLow, effortMedium, effortHigh, effortXhigh

    // MARK: - permission_mode（五種）
    /// `auto` 的語意是「自動決定要不要問」，不是一律接受——中英文都必須避免讀起來像
    /// 「全部自動接受」（那是 `bypassPermissions` 的語意，S2-3 已經在中文版點名過這個混淆）。
    case permissionAuto
    case permissionDefault
    case permissionAcceptEdits
    case permissionBypass
    case permissionPlan

    public func text(_ language: Language) -> String {
        switch self {
        case .effortLow:
            switch language {
            case .english: return "Low"
            case .traditionalChinese: return "思考低"
            }
        case .effortMedium:
            switch language {
            case .english: return "Medium"
            case .traditionalChinese: return "思考中"
            }
        case .effortHigh:
            switch language {
            case .english: return "High"
            case .traditionalChinese: return "思考高"
            }
        case .effortXhigh:
            switch language {
            case .english: return "Max"
            case .traditionalChinese: return "思考極高"
            }
        case .permissionAuto:
            switch language {
            case .english: return "Auto-decide"
            case .traditionalChinese: return "自動判斷"
            }
        case .permissionDefault:
            switch language {
            case .english: return "Ask every time"
            case .traditionalChinese: return "每次問我"
            }
        case .permissionAcceptEdits:
            switch language {
            case .english: return "Auto-accept edits"
            case .traditionalChinese: return "自動接受編輯"
            }
        case .permissionBypass:
            switch language {
            case .english: return "Auto-approve all"
            case .traditionalChinese: return "全部自動"
            }
        case .permissionPlan:
            switch language {
            case .english: return "Plan mode"
            case .traditionalChinese: return "計畫模式"
            }
        }
    }
}
