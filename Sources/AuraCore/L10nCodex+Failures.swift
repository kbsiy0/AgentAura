/// T09：`L10nCodex` 本體（case 宣告 ＋ `text(_:)`）留在 `L10nCodex.swift`——Swift enum 的
/// case 不能用 extension 補（`L10nCatalog` doc comment 的既有理由）。這裡放**不需要新增
/// case**、只是帶參數的部分：字元／錯誤碼插值（同 `L10nSessionRow.subtaskCount` 的既有手法），
/// 以及 `CodexFailure` 七個 case → banner 文案的窮盡 dispatcher（同
/// `PanelBanner+InstallerFailure.message(for:language:)` 的既有形狀）——把「哪個 case 用哪句」
/// 的邏輯跟「哪個鍵兩種語言各是什麼」分兩個檔案，同 `L10nInstallAffordance` 的既有切法。
extension L10nCodex {

    /// 帶括注的人話字元名——空白／換行／Tab 三個字元直接印出來看不出差異或會破壞排版，
    /// 其餘（`'`／`"`／`$`／`` ` ``／`\`）本身已經夠清楚，不额外加註。
    ///
    /// **不用 `switch`**：`Character` 的可能值不是封閉集合，任何 `switch` 都得靠那個
    /// D-5(1) 禁用的收尾分支才編得過，而 `L10nExhaustivenessSourceScanTests` 對
    /// `Sources/AuraCore/L10n*.swift` 是整份檔案文字掃描那個字面（地基：字串表的窮盡
    /// switch 不准有它），不分辨這個 `switch` 是對 `Character` 還是對 `Language`——
    /// 改用 `if`／`else` 鏈完全避開那個字面（同這條 gate 自己的原始碼避免自我命中的解法）。
    private static func clarifier(for character: Character, language: Language) -> String? {
        if character == " " { return language == .english ? "space" : "空白" }
        if character == "\n" { return language == .english ? "newline" : "換行" }
        if character == "\t" { return language == .english ? "tab" : "Tab" }
        return nil
    }

    /// R-5／CX36 mutation④ 的守衛：**必須把字元本身插進句子**，不能只講「路徑含有不支援的
    /// 字元」這種籠統句——`CodexSectionView`（面板卡片）與 `failureMessage(_:language:)`
    /// （banner）共用同一個 oracle，改壞任何一處用字都會被 CX33／CX36 兩條姊妹 gate 之一抓到。
    public static func unsupportedCharacterExplanation(_ character: Character, language: Language) -> String {
        let clarifierText = clarifier(for: character, language: language)
        switch language {
        case .english:
            let suffix = clarifierText.map { " (\($0))" } ?? ""
            return "AgentAura's own path contains \"\(character)\"\(suffix), which could break the file Codex reads."
        case .traditionalChinese:
            let suffix = clarifierText.map { "（\($0)）" } ?? ""
            return "AgentAura 目前所在的路徑含有「\(character)」\(suffix)，可能讓 Codex 讀到的設定檔壞掉。"
        }
    }

    /// m4（spec-reviewer 2026-09-18）：涵蓋 `open`（建立）／寫入／`unlink`（刪除）三種
    /// syscall 失敗，文案**不寫死「寫入」**——同 `CodexFailure.writeFailed` 的 doc comment。
    public static func writeFailedMessage(code: Int32, language: Language) -> String {
        switch language {
        case .english: return "Something went wrong with Codex's hook file (error code \(code))."
        case .traditionalChinese: return "處理 Codex 的 hook 設定檔時失敗（錯誤碼 \(code)）。"
        }
    }

    public static func unreadableMessage(code: Int32, language: Language) -> String {
        switch language {
        case .english: return "Couldn't read Codex's hook file (error code \(code))."
        case .traditionalChinese: return "讀取 Codex 的 hook 設定檔時失敗（錯誤碼 \(code)）。"
        }
    }

    /// `CodexFailure` 七個 case → banner 文案，單一窮盡來源。`AppDelegate+Codex.swift`
    /// （T10）是唯一預期呼叫點——同 `PanelBanner.error(for: InstallerFailure, language:)`
    /// 對 Claude 側的既有形狀。窮盡 `switch`：新增 `CodexFailure` case 這裡編不過，
    /// 逼你同時補齊文案，不是事後才發現漏了一種失敗沒有措辭。
    ///
    /// `.mustMoveToApplications`／`.unsupportedPathCharacter` 兩個 case **重用**既有措辭
    /// （`InstallerFailure.mustMoveToApplicationsMessage`／`unsupportedCharacterExplanation`）——
    /// 不維護第二份「App 要搬進應用程式」或「字元指名」的字面，同一個實體理由只該有一份措辭。
    public static func failureMessage(_ failure: CodexFailure, language: Language) -> String {
        switch failure {
        case .codexHomeMissing: return L10nCodex.codexHomeMissingBanner.text(language)
        case .alreadyExists: return L10nCodex.alreadyExistsBanner.text(language)
        case .writeFailed(let code): return writeFailedMessage(code: code, language: language)
        case .notOurs: return L10nCodex.notOursBanner.text(language)
        case .unreadable(let code): return unreadableMessage(code: code, language: language)
        case .mustMoveToApplications: return InstallerFailure.mustMoveToApplicationsMessage(language)
        case .unsupportedPathCharacter(let character):
            return unsupportedCharacterExplanation(character, language: language)
        }
    }
}
