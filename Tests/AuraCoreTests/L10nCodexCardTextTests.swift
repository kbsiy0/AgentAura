import Testing
import AuraCore

/// T09：`L10nCodex`（T09 追加的部分）——面板卡片說明句、`CodexFailure` 窮盡 dispatcher、
/// D-m 接上成功 banner。**不測 T07 既有的 `connectRow`／`reconnectRow`／
/// `disconnectMountRow`**（已有 `OptionsMenuModelTests`／`HelpDocOptionsRowCoverageTests`
/// 覆蓋），這裡只補 T09 新增的鍵。
@Suite("L10nCodex（T09 追加）：卡片說明句、CodexFailure banner、D-m")
struct L10nCodexCardTextTests {

    /// D-5(1)：兩個語言各自要有非空文字——這條不是「翻譯品質」的把關，是「忘了翻某個語言」
    /// 的把關（同 `L10nCatalog` 窮盡 switch 的既有理由，這裡額外用型別走一輪確認没有漏）。
    @Test("每個 case 兩種語言都非空", arguments: Array(L10nCodex.allCases))
    func everyCaseHasNonEmptyTextInBothLanguages(codexCase: L10nCodex) {
        for language in Language.allCases {
            #expect(!codexCase.text(language).isEmpty,
                    "\(codexCase) 在 \(language) 沒有文字")
        }
    }

    /// R-5／CX36 mutation④ 的守衛前身：字元真的被插進句子，不是回一句籠統話。
    /// 涵蓋 `CodexHookPathCheck.unsupportedCharacters` 全部八個字元（定義域推導，不手列）。
    @Test("unsupportedCharacterExplanation 把字元本身插進句子", arguments: Array(CodexHookPathCheck.unsupportedCharacters), Language.allCases)
    func unsupportedCharacterExplanationNamesTheCharacter(character: Character, language: Language) {
        let text = L10nCodex.unsupportedCharacterExplanation(character, language: language)
        #expect(text.contains(String(character)), """
            字元「\(character)」沒有出現在 \(language) 的解釋句裡：\(text) —— \
            這句只講「有個不支援的字元」這種籠統話，使用者猜不到是哪一個
            """)
    }

    /// 正向對照：兩個不同字元的解釋句必須不同（不是同一句籠統話套上不同字元參數卻被忽略）。
    @Test("正向對照：不同字元給出不同的解釋句")
    func differentCharactersProduceDifferentExplanations() {
        let space = L10nCodex.unsupportedCharacterExplanation(" ", language: .english)
        let backslash = L10nCodex.unsupportedCharacterExplanation("\\", language: .english)
        #expect(space != backslash, "空白與反斜線的解釋句應該不同，實際都是：\(space)")
    }

    /// D-m 硬下限（P4）：接上成功 banner 必須**同時**含兩個關鍵詞。`CodexWiringSmokeTests`
    /// （CX24④）用 `.english`（`AppDelegate.language` 預設值）建 delegate 讀這句，
    /// 這裡把「兩個關鍵詞是 connectedBanner.text(.english) 的逐字子字串」釘死，
    /// 避免兩處漂移（改了 `connectedBanner` 忘了同步關鍵詞常數）。
    @Test("connectedBanner 同時含「下一個 session 起生效」與「信任」兩個關鍵詞")
    func connectedBannerContainsBothRequiredKeywords() {
        let english = L10nCodex.connectedBanner.text(.english)
        #expect(english.contains(L10nCodex.nextSessionTakesEffectKeyword), """
            connectedBanner 的英文版沒有包含 \(L10nCodex.nextSessionTakesEffectKeyword)：\(english)
            """)
        #expect(english.contains(L10nCodex.codexWillAskToTrustKeyword), """
            connectedBanner 的英文版沒有包含 \(L10nCodex.codexWillAskToTrustKeyword)：\(english)
            """)
        // 中文版同樣的兩個概念（不比對逐字關鍵詞——關鍵詞常數只保證跟英文版同源）。
        let chinese = L10nCodex.connectedBanner.text(.traditionalChinese)
        #expect(chinese.contains("下一個 Codex session"), "中文版沒有講「下一個 Codex session」：\(chinese)")
        #expect(chinese.contains("信任"), "中文版沒有講「信任」：\(chinese)")
    }

    /// `PanelBanner.codexConnected(language:)` 讀的正是這句，不是另外手搓一份。
    @Test("PanelBanner.codexConnected 讀 L10nCodex.connectedBanner，不是另一份字面")
    func panelBannerCodexConnectedUsesTheSameOracle() {
        let banner = PanelBanner.codexConnected(language: .english)
        #expect(banner.text == L10nCodex.connectedBanner.text(.english))
        // T13b（D-v）：走它自己的 `.codexConnected` kind（不再沿用 `.connected`）才有自己的
        // 退場條件——`BannerView.background` 只把 `.error` 特判成紅色，其餘 kind（含這個新的）
        // 一律走同一套成功色（`Color.accentColor.opacity(0.12)`），視覺樣式不受影響。
        #expect(banner.kind == .codexConnected, "D-v 之後應該是它自己的 kind，不是共用 .connected")
    }

    /// `CodexFailure` 七個 case 的窮盡 dispatcher——涵蓋每一個 case，錯誤碼／字元有插值。
    @Test("failureMessage 窮盡涵蓋七個 CodexFailure case")
    func failureMessageCoversAllSevenCases() {
        let cases: [CodexFailure] = [
            .codexHomeMissing, .alreadyExists, .writeFailed(13), .notOurs,
            .unreadable(13), .mustMoveToApplications, .unsupportedPathCharacter(" "),
        ]
        for failure in cases {
            for language in Language.allCases {
                #expect(!L10nCodex.failureMessage(failure, language: language).isEmpty,
                        "\(failure) 在 \(language) 沒有 banner 文案")
            }
        }
    }

    /// m4：`.writeFailed` 涵蓋建立／寫入／`unlink` 三種 syscall 失敗，文案不該寫死「寫入」
    /// 這種只描述一種情境的字——用「寫入」以外還要站得住的詞來判斷（不要求逐字，只要求
    /// 不是那個過度具體的舊詞）。
    @Test("writeFailedMessage 不寫死「寫入」")
    func writeFailedMessageDoesNotHardcodeWriting() {
        let text = L10nCodex.writeFailedMessage(code: 13, language: .traditionalChinese)
        #expect(!text.contains("寫入"), "writeFailedMessage 的措辭寫死了「寫入」，涵蓋不到 unlink 失敗：\(text)")
        #expect(text.contains("13"), "錯誤碼沒有插進句子：\(text)")
    }

    /// `.mustMoveToApplications`／`.unsupportedPathCharacter` 兩個 case 重用既有措辭
    /// （不維護第二份「把 App 移到應用程式」或「字元指名」的字面）。
    @Test("mustMoveToApplications 與 unsupportedPathCharacter 重用既有措辭，不是第二份字面")
    func reusesExistingWording() {
        #expect(L10nCodex.failureMessage(.mustMoveToApplications, language: .english)
                == InstallerFailure.mustMoveToApplicationsMessage(.english))
        #expect(L10nCodex.failureMessage(.unsupportedPathCharacter("$"), language: .english)
                == L10nCodex.unsupportedCharacterExplanation("$", language: .english))
    }

    /// review m3：`disconnectedBanner`／`PanelBanner.codexDisconnected` 在 T10 之前零測試
    /// 引用——唯一觸及它的是 `banner?.kind == .disconnected`，而 Claude 側的斷開 banner
    /// 也滿足那條，不是內容專屬的守衛。比照 `panelBannerCodexConnectedUsesTheSameOracle`
    /// 補一條內容 pin：`PanelBanner.codexDisconnected` 讀的是 `L10nCodex.disconnectedBanner`
    /// 本身，不是另外手搓一份字面；且措辭刻意**不提任何按鈕**（Claude 側寫「要再用的話按
    /// ［接上］」，這裡照抄會提到一顆不存在的按鈕，`disconnectedBanner` 的 doc comment
    /// 已載明這個理由）。
    @Test("PanelBanner.codexDisconnected 讀 L10nCodex.disconnectedBanner，不是另一份字面，且不提任何按鈕")
    func panelBannerCodexDisconnectedUsesTheSameOracle() {
        let banner = PanelBanner.codexDisconnected(language: .english)
        #expect(banner.text == L10nCodex.disconnectedBanner.text(.english))
        #expect(banner.kind == .disconnected, "拆掉 Codex 掛載成功的視覺樣式應該是 .disconnected")
        #expect(!banner.text.contains("Connect"), """
            斷開 banner 不該提任何按鈕字樣（Claude 側「要再用的話按［接上］」的措辭在這裡不適用，
            Codex 側按鈕字樣是「接上 Codex」／「重新接上 Codex」），實際：\(banner.text)
            """)
    }
}
