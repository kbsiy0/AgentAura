import Testing
import AuraCore
import Foundation

/// `bannerBeatsCTABanner`（spec §3.3／N10）：banner 與 CTA 的優先序——同一時間畫面
/// 上方最多一條窄條。`banner != nil` 時 `.banner` 樣式降級為 `.none`（banner 贏）；
/// `.fullPanel`（rows 空的整版 CTA）與 banner 可以並存，banner 在上。
@Suite("PanelModel banner 與 CTA 優先序（bannerBeatsCTABanner）")
struct PanelModelBannerTests {

    static let icon = IconState(activity: .working, counts: [.working: 1], liveCount: 1)

    static func session(_ id: String) -> SessionState {
        SessionState(id: id, projectName: id,
                    permissionMode: nil, effort: nil, model: nil,
                    activity: .working, mainActivity: .working, subActivity: nil,
                    currentTool: "Bash", subagentTool: nil, toolDurationMs: nil,
                    turnStartedAt: nil, subagents: [:], toolFailures: 0,
                    lastMessage: nil, errorType: nil, toolError: nil,
                    liveness: .alive(pid: 1), updatedAt: Date())
    }

    /// `.notConnected` 的 affordance 是 `.connect` → `showsConnectCTA == true`，
    /// 是這條 gate 唯一在乎的前提（banner 優先序跟「哪一種」affordance 無關）。
    static func model(sessions: [SessionState], banner: PanelBanner?) -> PanelModel {
        PanelModel.make(icon: icon, sessions: sessions, palette: .default,
                        install: .notConnected, version: "1.0", optionsExpanded: false,
                        launchAtLogin: nil, externalTargetPath: nil, banner: banner, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese)
    }

    @Test("前提：rows 空、無 banner → .fullPanel；有列、無 banner → .banner")
    func baselineStylesWithoutBanner() {
        #expect(Self.model(sessions: [], banner: nil).connectCTAStyle == .fullPanel)
        #expect(Self.model(sessions: [Self.session("a")], banner: nil).connectCTAStyle == .banner)
    }

    @Test("banner != nil 且 rows 非空（本應是 .banner）→ 降級為 .none，banner 贏")
    func bannerDegradesCTABannerToNone() {
        let model = Self.model(sessions: [Self.session("a")], banner: .disconnected(language: .traditionalChinese))
        #expect(model.banner != nil)
        #expect(model.connectCTAStyle == .none, "有 banner 時 CTA 不得再顯示成另一條窄條——畫面上方只准一條")
    }

    @Test("banner != nil 且 rows 空（.fullPanel）→ 並存，CTA 仍是 .fullPanel")
    func bannerCoexistsWithFullPanelCTA() {
        let model = Self.model(sessions: [], banner: .disconnected(language: .traditionalChinese))
        #expect(model.banner != nil)
        #expect(model.connectCTAStyle == .fullPanel, """
            rows 空的整版 CTA 與 banner 可以並存，banner 只是疊在上面，不吃掉整版 CTA
            """)
    }

    @Test("已接上（showsConnectCTA == false）時任何 banner 都不影響 connectCTAStyle，恆 .none")
    func noCTAWhenAlreadyConnectedRegardlessOfBanner() {
        let model = PanelModel.make(icon: Self.icon, sessions: [], palette: .default,
                                    install: .connected(owner: .thisApp, verified: .verified),
                                    version: "1.0", optionsExpanded: false,
                                    launchAtLogin: nil, externalTargetPath: nil, banner: .connected(language: .traditionalChinese), systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese)
        #expect(model.connectCTAStyle == .none)
    }

    // MARK: - A7：banner 生命週期

    /// persona 實測：「已接上 · 下一個 session 起生效」在它宣稱的條件被滿足之後（真的出現
    /// 第一個 session）還一直留著，佔面板頂端 40pt。`.connected` banner 應該在 rows 非空
    /// 之後自動退場——不需要使用者按 ✕。
    @Test("A7：connected banner 在真的出現第一個 session 之後自動消失")
    func connectedBannerClearsOnceSessionAppears() {
        let withoutRows = Self.model(sessions: [], banner: .connected(language: .traditionalChinese))
        #expect(withoutRows.effectiveBanner != nil, "還沒有任何 session 之前，成功 banner 應該還在")

        let withRows = Self.model(sessions: [Self.session("a")], banner: .connected(language: .traditionalChinese))
        #expect(withRows.effectiveBanner == nil, "已經出現第一個 session（banner 宣稱的條件已滿足），成功 banner 應該自動清除")
        #expect(withRows.banner != nil, "banner 這個原始欄位（AppDelegate 存的那份）不受影響——effectiveBanner 只是顯示層推導")
    }

    @Test("A7：其餘 banner（disconnected／error／alreadyConnected）不因 rows 非空自動消失")
    func nonConnectedKindBannersDoNotAutoClear() {
        for banner in [PanelBanner.disconnected(language: .traditionalChinese), .error("x"), .alreadyConnected(target: nil, language: .traditionalChinese)] {
            let model = Self.model(sessions: [Self.session("a")], banner: banner)
            #expect(model.effectiveBanner != nil, "\(banner.kind) 不該因為 rows 非空就自動消失")
        }
    }

    // MARK: - A5：.banner 版 CTA 副標 ＋ mountReplaced 文案

    @Test("A5：connectCTASubtitle 只在 .replaceExternal 且有 externalTargetPath 時非 nil")
    func connectCTASubtitleOnlyForReplaceExternal() {
        let replaceExternal = PanelModel.make(icon: Self.icon, sessions: [], palette: .default,
                                              install: .broken(.hookMissing, owner: .external), version: "1.0",
                                              optionsExpanded: false, launchAtLogin: nil,
                                              externalTargetPath: "/Users/dev/repo/plugin", banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese)
        #expect(replaceExternal.connectCTASubtitle == "現有掛載指向：/Users/dev/repo/plugin")

        let connect = PanelModel.make(icon: Self.icon, sessions: [], palette: .default,
                                      install: .notConnected, version: "1.0", optionsExpanded: false,
                                      launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese)
        #expect(connect.connectCTASubtitle == nil, ".connect affordance 沒有「現有掛載指向」可顯示")
    }

    @Test("A5：mountReplaced(from:) 文案明說原掛載路徑；nil 時不留懸空括號")
    func mountReplacedTextMentionsPriorTarget() {
        let withTarget = PanelBanner.mountReplaced(from: "/Users/dev/repo/plugin", language: .traditionalChinese)
        #expect(withTarget.text.contains("/Users/dev/repo/plugin"), "應該明說原掛載路徑，實際「\(withTarget.text)」")
        #expect(withTarget.kind == .connected, "mountReplaced 沿用 .connected kind（視覺上仍是成功樣式）")

        let withoutTarget = PanelBanner.mountReplaced(from: nil, language: .traditionalChinese)
        #expect(!withoutTarget.text.contains("（原掛載："), "target 為 nil 時不該留下懸空的「（原掛載：」，實際「\(withoutTarget.text)」")
    }
}
