import Testing
import Foundation
@testable import AgentAuraApp
import AuraCore

/// G7（spec §6.3）：`optionsExpanded` 展開後 `preferredContentSize.height` 變高。
/// **快照比對**——`PanelHostingTests.hostingControllerIsReused` 踩過「拿當下值跟自己比」
/// 恆假的坑（同一個 hosting controller 實例，高度要在當下時刻先存起來，不能事後再讀）。
@MainActor
@Suite("Options 展開讓面板變高（G7）", .serialized)
struct OptionsExpandTests {

    func model(optionsExpanded: Bool, launchAtLogin: Bool? = true) -> PanelModel {
        let icon = IconState(activity: .idle, counts: [:], liveCount: 0)
        return PanelModel.make(icon: icon, sessions: [], palette: .default,
                               install: .connected(owner: .thisApp, verified: .verified),
                               version: "1.0", optionsExpanded: optionsExpanded,
                               launchAtLogin: launchAtLogin, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese)
    }

    @Test("同一個 hostingController：collapsed → setPanel(expanded) 後 preferredContentSize.height 變高")
    func expandingOptionsGrowsPreferredContentSize() throws {
        let controller = StatusItemController()
        defer { controller.removeFromStatusBar() }

        controller.setPanel(model(optionsExpanded: false))
        let collapsed = try #require(controller.hostingController, "第一次 setPanel 之後 hostingController 應該非 nil")
        let collapsedHeight = collapsed.preferredContentSize.height   // 快照，不是事後再讀同一個實例

        controller.setPanel(model(optionsExpanded: true))
        let expanded = try #require(controller.hostingController)
        #expect(collapsed === expanded, "應該重用同一個 hostingController 實例")
        let expandedHeight = expanded.preferredContentSize.height

        #expect(expandedHeight > collapsedHeight, """
            展開 Options 後高度應變高，實際 collapsed=\(collapsedHeight) expanded=\(expandedHeight)
            """)

        // 收合回去應該變矮——同一個 gate 順便驗證雙向都吃得到 optionsExpanded，不只是「單調變大」。
        controller.setPanel(model(optionsExpanded: false))
        let collapsedAgain = try #require(controller.hostingController)
        #expect(collapsedAgain.preferredContentSize.height < expandedHeight, """
            收合 Options 後高度應變矮，實際 \(collapsedAgain.preferredContentSize.height) vs \(expandedHeight)
            """)
    }

    /// A10（T11 commit3，team-lead 自查）：team-lead 實測 8 列全展開＋一行掛載目標，
    /// 診斷量到 405pt——比整個 session 列表區還高，逼近把 session 列全部推出可視範圍的風險
    /// （`sizingOptions` 會自動長高，長到團隊主管講的 900pt 就是壞的）。修完（列的垂直 padding
    /// 6pt→3pt）同一個 worst-case 重量一次：357pt。
    ///
    /// C2（team-lead 收尾）：門檻不再是手動調的魔術數字——`OptionsPanelSizing.heightCeiling(
    /// forRowCount:)` 從**當下真的算出來的列數**推導（見該型別 doc comment 的實測分解）。
    /// 好處：下次再加一列（合理成長）門檻自動跟上，不必回來改這條測試；某一列自己變胖
    /// （不合理成長，如 padding 被改壞）門檻不動、量到的高度會超過它——**這條測試本身**
    /// 就是 mutation 抓得到的那個（實測把一列 padding 從 3pt 改到 15pt，高度衝到 603pt，
    /// 遠超推導門檻 460pt，立即紅）。這裡的 worst-case 是
    /// `owner: .external, verified: .unknown`（觸發 `recheckHook`）＋ `launchAtLogin: true`
    /// ＋ `systemReduceMotion: true`（減少動態列多印 subtitle）＋ external 目標行——十列全到齊。
    ///
    /// T19（對齊新契約，非弱化）：`iconPlate: false` ＋ `.default` palette——底板關閉時
    /// 白色 working 觸發 `ContrastCheck.lowOnLightBar`，「燈條底板」列現在也會多印一行
    /// subtitle。這條測試名叫「worst-case」，加了第二種能觸發 subtitle 的條件之後，
    /// 原本 `iconPlate: true` 的版本不再是真正的最壞情境——兩列 subtitle 同時出現才是。
    /// `OptionsPanelSizing.chromeCeiling` 的 32pt margin（見該型別 doc comment）本來就是
    /// 為了吸收「不隨列數線性成長的變異」，多一行 3pt subtitle 仍在這個 margin 內。
    ///
    /// **單位一律是 pt，不是 px**（S2-7 同一種錯的回歸）：`preferredContentSize.height` 本身
    /// 就是 AppKit 的點座標系統，不需要換算；真正容易搞混的是**肉眼看 @2x PNG 截圖**時，
    /// 影像像素要除以 2 才是 pt（team-lead 第一版量錯就是把螢幕截圖的 56px 直接當 56pt）。
    /// 這條 gate 全程沒有碰截圖，讀的是真的 `NSHostingController.preferredContentSize`。
    @Test("worst-case（全部列展開 ＋ external 目標行 ＋ 減少動態／燈條底板兩個 subtitle）preferredContentSize.height 不超過推導門檻")
    func expandedHeightStaysWithinCeiling() throws {
        let controller = StatusItemController()
        defer { controller.removeFromStatusBar() }
        let install = InstallState.connected(owner: .external, verified: .unknown)
        let launchAtLogin = true
        let systemReduceMotion = true
        // T07：PanelModel 還沒有 codex 欄位（T08 才加），先傳 .unavailable/nil——這條 gate
        // 驗的是「worst-case 高度不超過從 rowCount 推導的門檻」，Codex 目前零列不影響 worst-case。
        let rowCount = OptionsMenuModel.rows(install: install, launchAtLogin: launchAtLogin, isDefaultPalette: true,
                                             systemReduceMotion: systemReduceMotion, userReduceMotion: false,
                                             iconPlate: false, iconShape: .ledStrip, palette: .default, language: .traditionalChinese,
                                             codex: .unavailable, codexPathRejection: nil).count
        let worstCase = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                        install: install, version: "1.0",
                                        optionsExpanded: true, launchAtLogin: launchAtLogin,
                                        externalTargetPath: "/Users/dev/some/very/long/path/to/repo/plugin", banner: nil,
                                        systemReduceMotion: systemReduceMotion, userReduceMotion: false, iconPlate: false, iconShape: .ledStrip, language: .traditionalChinese)
        controller.setPanel(worstCase)
        let height = try #require(controller.hostingController).preferredContentSize.height
        let ceiling = OptionsPanelSizing.heightCeiling(forRowCount: rowCount)
        #expect(Double(height) <= ceiling, """
            worst-case Options 展開高度 \(height)pt 超過推導門檻 \(ceiling)pt（\(rowCount) 列）—— \
            可能有列自己變胖了，不是單純多了幾列
            """)
    }
}
