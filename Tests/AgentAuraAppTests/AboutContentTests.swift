import Testing
import AppKit
import Foundation
@testable import AgentAuraApp
import AuraCore

/// T12（B4）：「關於」面板此前只是 `NSApp.orderFrontStandardAboutPanel(nil)`——完全空的
/// standard panel，使用者看到的是「什麼都沒有」。這裡直接測 `AboutContent.options(version:)`
/// 這個純函式（不經過 `AppDelegate`，版本字串因此不受 `swift test` 沒有 app bundle 影響），
/// composition 端的接線由 `AppDelegatePanelActionsWiredTests+T12.swift` 的 `verifyAbout` 守。
@Suite("B4：關於面板帶實際內容（AboutContent）")
struct AboutContentTests {

    @Test("options(version:language:) 含指定的版本字串")
    func containsGivenVersion() {
        let options = AboutContent.options(version: "0.1.0", language: .traditionalChinese)
        #expect(options[.applicationVersion] as? String == "0.1.0")
    }

    @Test("options(version:language:) 的 credits 含專案網址且可點擊（.link 屬性）")
    func creditsContainsClickableProjectLink() throws {
        let options = AboutContent.options(version: "0.1.0", language: .traditionalChinese)
        let credits = try #require(options[.credits] as? NSAttributedString, "應該有 .credits 欄位")
        #expect(credits.string.contains(ProjectLinks.repository.absoluteString), """
            credits 文字應含專案網址，實際「\(credits.string)」
            """)
        // 不只字面含網址字串——要真的可點（NSTextView 顯示 .credits 時吃這個屬性）。
        var foundLink: URL?
        credits.enumerateAttribute(.link, in: NSRange(location: 0, length: credits.length)) { value, _, _ in
            if let url = value as? URL { foundLink = url }
        }
        #expect(foundLink == ProjectLinks.repository, "credits 應該有一段 .link 屬性指到專案網址")
    }

    @Test("options(version:language:) 的 credits 含授權說明，且照實寫「尚未決定」——不得瞎掰授權名字")
    func creditsContainsHonestLicenseText() throws {
        let options = AboutContent.options(version: "0.1.0", language: .traditionalChinese)
        let credits = try #require(options[.credits] as? NSAttributedString)
        #expect(credits.string.contains("尚未決定"), """
            README §授權目前是「尚未決定（開源時確定）」——credits 必須照實寫，不能寫成
            MIT／Apache 之類瞎掰的授權名字，實際「\(credits.string)」
            """)
    }

    /// T29（i18n）：英文那半的對照——同樣照實寫「尚未決定」，不瞎掰授權名字，
    /// 只是換一種語言講同一件事。
    @Test("英文 options(version:language:) 的 credits 同樣照實寫授權未決定，不瞎掰")
    func englishCreditsContainsHonestLicenseText() throws {
        let options = AboutContent.options(version: "0.1.0", language: .english)
        let credits = try #require(options[.credits] as? NSAttributedString)
        #expect(credits.string.contains("not yet decided"), """
            英文版 credits 應該照實寫授權尚未決定，不能寫成 MIT／Apache 之類瞎掰的授權名字，
            實際「\(credits.string)」
            """)
        for banned in ["MIT", "Apache", "BSD", "GPL"] {
            #expect(!credits.string.contains(banned), "英文 credits 不該出現瞎掰的授權名字「\(banned)」")
        }
    }

    @Test("兩種語言的 credits 文字不同——不是共用同一個寫死字面")
    func licenseTextDiffersByLanguage() {
        let zh = AboutContent.license(.traditionalChinese)
        let en = AboutContent.license(.english)
        #expect(zh != en, "中英文授權說明不該是同一個字面")
    }

    @Test("不同版本字串各自反映在 options 裡——不是寫死的常數")
    func differentVersionsProduceDifferentOptions() {
        let a = AboutContent.options(version: "1.0.0", language: .traditionalChinese)
        let b = AboutContent.options(version: "2.0.0", language: .traditionalChinese)
        #expect(a[.applicationVersion] as? String != b[.applicationVersion] as? String)
    }

    /// T13（persona 附帶發現）：standard about panel 的版權行完全由 AppKit 從執行中 bundle 的
    /// `Info.plist` 讀 `NSHumanReadableCopyright`——`AboutPanelOptionKey` 沒有對應的 case，
    /// `AboutContent.options(version:)` 沒有機會覆寫，所以缺這個鍵時「關於」面板就是沒有
    /// 版權行，跟版本／credits 是否寫對無關。沿用 `InstallLayoutTests` 從 `#filePath` 找
    /// repo root、直接讀 `Resources/Info.plist` 的既有慣例（同一個 target 看不到
    /// `AuraCoreTests` 的 `Gate`，各自維護一份小型 repoRoot()）。
    static func repoRoot() -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        while dir.pathComponents.count > 1 {
            dir = dir.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir
            }
        }
        fatalError("找不到 Package.swift")
    }

    @Test("Resources/Info.plist 含非空的 NSHumanReadableCopyright")
    func infoPlistHasHumanReadableCopyright() throws {
        let url = Self.repoRoot().appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
            "Resources/Info.plist 應該能被解析成字典"
        )
        let copyright = plist["NSHumanReadableCopyright"] as? String
        #expect(copyright?.isEmpty == false, """
            Resources/Info.plist 缺 NSHumanReadableCopyright（或是空字串）——
            少了這個鍵，standard about panel 不會有版權行，AboutContent 這邊無從補救
            """)
    }
}
