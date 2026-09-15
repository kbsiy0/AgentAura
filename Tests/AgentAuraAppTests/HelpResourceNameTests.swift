import Testing
@testable import AgentAuraApp
import AuraCore

/// T30（i18n）：`AppDelegate.helpResourceName(for:)` 是 `openHelp()` 依語言選檔的純函式
/// 部分——`Bundle.main` 在 `swift test` 沙盒裡拿不到任何 `help-*.html`（見
/// `AppDelegatePanelActionsWiredTests+E3.swift` 的既有說明），所以「按下去真的開對語言的
/// 檔案」這件事沒辦法在沙盒裡端到端驗證；這裡只驗證「語言 → 檔名」這條純公式本身，
/// 不摸 `Bundle`。**期望值是字面，不是拿 `rawValue` 重算一次**——否則等於拿同一條公式
/// 驗自己，公式本身錯了測試也看不出來。
@Suite("T30：helpResourceName(for:) 依語言選檔名")
struct HelpResourceNameTests {

    @Test("English 對應 help-english")
    func englishFileName() {
        #expect(AppDelegate.helpResourceName(for: .english) == "help-english")
    }

    @Test("繁體中文對應 help-traditionalChinese")
    func traditionalChineseFileName() {
        #expect(AppDelegate.helpResourceName(for: .traditionalChinese) == "help-traditionalChinese")
    }

    /// D-6（YAGNI）：目前只有兩個 `Language` case。這條斷言鎖住「兩個字面期望值涵蓋
    /// Language.allCases 的全部」——哪天真的加第三個 case，這裡會先紅，提醒你同時補一份
    /// `Resources/help-<新case>.html` 與這裡的期望值，而不是讓 gate 悄悄漏掉新語言。
    @Test("兩個字面期望值涵蓋 Language.allCases 全部")
    func expectationsCoverAllLanguageCases() {
        let expected: [Language: String] = [.english: "help-english", .traditionalChinese: "help-traditionalChinese"]
        #expect(Set(expected.keys) == Set(Language.allCases), """
            Language.allCases 是 \(Language.allCases)，跟這裡手寫的期望值鍵集合對不上——
            新增 Language case 時要同時在這裡補一筆期望檔名
            """)
        for language in Language.allCases {
            #expect(AppDelegate.helpResourceName(for: language) == expected[language])
        }
    }
}
