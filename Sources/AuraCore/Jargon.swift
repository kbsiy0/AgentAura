import Foundation

/// 面板文案去工程師化（M-7，D-c，spec §3.4）：把 hook payload 裡的機器代碼換成人話。
/// tool 名保留原文（D-c：終端機裡本來就長那樣，翻了反而對不起來），
/// `model`／`effort`／`permission_mode` 是唯一要翻的三個欄位。
///
/// `effortMap`／`permissionModeMap` 用**字典**，不是 `switch`——G9a／G9b 要迭代它們
/// 本身當來源集合（S1-Q4），`switch` 推導不出 case 的完整集合。
///
/// T27（i18n）：兩個查表搬進 `L10nJargon` 字串表，這裡只是按語言把字典組出來——
/// **帶預設值 `.traditionalChinese`**（同 `OptionsMenuModel.rows` 的 T26 review 裁決）：
/// `FixtureCodeAnchorTests`／`JargonTests` 既有呼叫點很多，都不關心語言，改成無預設值
/// 會逼著一次改完所有呼叫點；生產路徑（`PanelViewModel.meta(for:)`）才是真正需要明確傳
/// `language` 的地方，見該檔案。
public enum Jargon {
    public static func effortMap(_ language: Language) -> [String: String] {
        [
            "low": L10nJargon.effortLow.text(language),
            "medium": L10nJargon.effortMedium.text(language),
            "high": L10nJargon.effortHigh.text(language),
            "xhigh": L10nJargon.effortXhigh.text(language),
        ]
    }

    /// `auto` 是實測 141 個真實 payload 裡**最常見**的值，r1 漏了它（S1-Q4）。
    /// brainstorm §4 的示意寫「自動接受」，這裡**刻意改成「自動判斷」**：
    /// auto 的語意是自動決定要不要問，不是一律接受（S2-3）。
    public static func permissionModeMap(_ language: Language) -> [String: String] {
        [
            "auto": L10nJargon.permissionAuto.text(language),
            "default": L10nJargon.permissionDefault.text(language),
            "acceptEdits": L10nJargon.permissionAcceptEdits.text(language),
            "bypassPermissions": L10nJargon.permissionBypass.text(language),
            "plan": L10nJargon.permissionPlan.text(language),
        ]
    }

    /// 查表，未命中原樣回傳——payload 的欄位是自由字串，映射不得吃掉資訊。
    public static func effort(_ raw: String, language: Language) -> String {
        effortMap(language)[raw] ?? raw
    }
    public static func permissionMode(_ raw: String, language: Language) -> String {
        permissionModeMap(language)[raw] ?? raw
    }

    /// 六條規則（spec §3.4，附反例表）：
    /// 1. 抓出 `[...]` 後綴 → ` (內容大寫)`；其餘部分繼續處理
    /// 2. 去 `claude-` 前綴（沒有也接受）
    /// 3. 去尾端的 8 位數字段（日期）
    /// 4. 以 `-` 切段；恰好一個非純數字段視為名字（首字大寫），其餘純數字段依原順序以 `.` 連接
    /// 5. 名字與版本之間一個半形空格
    /// 6. 任一步不符（無名字段、無數字段、多於一個非數字段）→ 原樣回傳
    public static func model(_ raw: String) -> String {
        var body = Substring(raw)
        var bracketSuffix = ""

        if body.hasSuffix("]"), let open = body.lastIndex(of: "["), open > body.startIndex {
            let inner = body[body.index(after: open)..<body.index(before: body.endIndex)]
            guard !inner.isEmpty else { return raw }
            bracketSuffix = " (\(inner.uppercased()))"
            body = body[body.startIndex..<open]
        }

        if body.hasPrefix("claude-") { body = body.dropFirst("claude-".count) }

        var segments = body.split(separator: "-").map(String.init)
        guard !segments.isEmpty else { return raw }

        if let last = segments.last, last.count == 8, last.allSatisfy(\.isNumber) {
            segments.removeLast()
        }
        guard !segments.isEmpty else { return raw }

        let nameSegments = segments.filter { !$0.allSatisfy(\.isNumber) }
        let versionSegments = segments.filter { $0.allSatisfy(\.isNumber) }
        guard nameSegments.count == 1, let name = nameSegments.first, !versionSegments.isEmpty else {
            return raw
        }

        let capitalizedName = name.prefix(1).uppercased() + name.dropFirst()
        return capitalizedName + " " + versionSegments.joined(separator: ".") + bracketSuffix
    }
}
