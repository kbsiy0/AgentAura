import Testing
import AuraCore

/// T13（S1-1 收尾）：把 A11 那條「標題／本體不得同句」的窮盡 gate 從 connected 一種狀態
/// 擴大到全部 `InstallState`——`NotConnectedView` 先前對每一種非 connected 狀態都把
/// `install.healthLabel` 印成本體標題，跟頂端 `PanelView.title`（非 connected 時恆等於
/// healthLabel，`TooltipAndTitleConsistencyTests` 已證明）撞成同一句；連同 footer chip
/// 是同一句 healthLabel 的第三次出現（persona r2 S1-1：「A2-broken-title-light.png」
/// 六行裡三行同句）。修法是本體不再重畫（見 `NotConnectedView.swift`），這裡用窮盡 gate
/// 釘住「以後也不准再撞回去」。
@Suite("面板標題／本體說明／footer chip 三者不得有兩者相同（T13，A11 從 connected 擴到全集）")
struct PanelBodyTitleChipDistinctTests {

    static func chipText(_ model: PanelModel) -> String {
        "\(model.install.healthLabel) · v\(model.version)"
    }

    /// `notConnectedDetailText` 是 `NotConnectedView` 唯一會顯示的本體說明句——`externalTargetPath`
    /// 這裡固定 nil，跟 G8a 系列其餘代表狀態集合一致，才踩得到 `explanationDetail` 分支
    /// （非 nil 時它的優先序更高，會蓋掉這條 gate 想驗的東西）。
    @Test("每一種非 connected InstallState：title／notConnectedDetailText／chip 兩兩不相同")
    func nonConnectedStatesHaveDistinctTitleBodyChip() {
        for install in InstallStateAllCases.all() {
            if case .connected = install { continue }
            let model = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                        install: install, version: "1.0", optionsExpanded: false,
                                        launchAtLogin: nil, externalTargetPath: nil, banner: nil,
                                        systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese, codex: .unavailable, codexSnippet: nil)
            let title = model.title
            let body = model.notConnectedDetailText
            let chip = Self.chipText(model)

            #expect(body != title, """
                \(install)：本體說明「\(body)」與標題「\(title)」相同——同一張畫面說了兩次同一句話（S1-1）
                """)
            #expect(body != chip, "\(install)：本體說明「\(body)」與 footer chip「\(chip)」相同")
            #expect(title != chip, "\(install)：標題「\(title)」與 footer chip「\(chip)」相同")
        }
    }

    /// A11 原本只管 `connected` ＋ rows 空這一種組合（`TooltipAndTitleConsistencyTests` 已經
    /// 蓋過），這裡補上 chip 這一角，讓「三者兩兩不相同」在 connected 側也是完整的三角驗證
    /// （不只是 body != title，是 body／title／chip 三個都互不相同）。
    @Test("connected ＋ rows 空：emptyRowsMessage／title／chip 兩兩不相同")
    func connectedEmptyRowsHasDistinctBodyTitleChip() {
        for owner in MountOwner.allCases {
            for verified in Verification.allCases {
                let install = InstallState.connected(owner: owner, verified: verified)
                let model = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                            install: install, version: "1.0", optionsExpanded: false,
                                            launchAtLogin: nil, externalTargetPath: nil, banner: nil,
                                            systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese, codex: .unavailable, codexSnippet: nil)
                let title = model.title
                let body = model.emptyRowsMessage
                let chip = Self.chipText(model)

                #expect(body != chip, "\(install)：本體說明「\(body)」與 footer chip「\(chip)」相同")
                #expect(title != chip, "\(install)：標題「\(title)」與 footer chip「\(chip)」相同")
            }
        }
    }
}
