import Testing
import AppKit
@testable import AgentAuraApp
import AuraCore

/// T12（B2／B4／B5）：`.about`／`.reportIssue`／`.setReduceMotion` 這三個 G5 case 的驗證體，
/// 搬出主檔只是為了不撞 `AppDelegatePanelActionsWiredTests.swift` 的 300 行 Tests 上限——
/// 沿用同一份 `withFreshRig`／`Rig`（同一個 test target，internal 可見）。
extension AppDelegatePanelActionsWiredTests {
    /// B4：不只斷言「被呼叫」——存下拿到的字典，驗版本字串與專案網址（見 `AboutContent`）。
    /// `swift test` 行程沒有 app bundle，`Bundle.main` 讀不到 `CFBundleShortVersionString`
    /// （既有 `AppDelegate.appVersion` 本來就是這樣算的，非本測試造成），所以版本字串比對
    /// 「與 delegate 算出來的是同一個值」而非斷言非空；非空字串由 `AboutContentTests`
    /// 這條不經過 `AppDelegate` 的單元測試守（直接給 `AboutContent.options` 固定版本字串）。
    @MainActor
    func verifyAbout(samples: [PanelAction]) async throws {
        try await withFreshRig { rig in
            for action in samples { rig.onAction(action) }
            let options = try #require(rig.recorder.aboutOptions, ".about 應該呼叫注入的 showAboutPanel")
            #expect(options[.applicationVersion] as? String == rig.delegate.appVersion, """
                about 選項的版本字串應該等於 AppDelegate.appVersion，實際 \(String(describing: options[.applicationVersion]))
                """)
            let credits = try #require(options[.credits] as? NSAttributedString,
                                       "about 選項應含 credits（承載專案網址）")
            #expect(credits.string.contains("github.com/kbsiy0/AgentAura"), """
                credits 應含專案網址，實際「\(credits.string)」
                """)
        }
    }

    /// B2：Amphetamine 的 Feedback & Support 對應——走注入的 `openURL`，斷言拿到正確的
    /// GitHub issues 網址，不得真的開瀏覽器。
    @MainActor
    func verifyReportIssue(samples: [PanelAction]) async throws {
        try await withFreshRig { rig in
            for action in samples { rig.onAction(action) }
            #expect(rig.recorder.openedURLs.last == ProjectLinks.newIssue, """
                .reportIssue 應該用注入的 openURL 開 GitHub issues 頁，實際 \(String(describing: rig.recorder.openedURLs.last))
                """)
        }
    }

    /// B5：兩個布林都要送（N7）；接線斷言分兩層——`delegate.userReduceMotion`（狀態本身）
    /// 與 `spy.panels.last?.userReduceMotion`（真的重畫過面板，不是只改了旗標沒人看得到）。
    @MainActor
    func verifySetReduceMotion(samples: [PanelAction]) async throws {
        try await withFreshRig { rig in
            #expect(samples.contains(.setReduceMotion(true)) && samples.contains(.setReduceMotion(false)),
                   "N7：兩個布林都要送，實際 \(samples)")
            for action in samples {
                guard case .setReduceMotion(let on) = action else { continue }
                rig.onAction(action)
                #expect(rig.delegate.userReduceMotion == on, ".setReduceMotion(\(on)) 之後 userReduceMotion 應為 \(on)")
                #expect(rig.spy.panels.last?.userReduceMotion == on, "面板 model 也應反映最新的 userReduceMotion")
            }
        }
    }
}
