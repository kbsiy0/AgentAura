import Testing
import AuraCore

/// T11 commit2（S0-2）：persona 實測 tooltip 在沒裝 hook 時一律說「沒有活著的 session」
/// （D-e 指定的「還沒接上 Claude Code」repo 0 命中），同一顆根因也讓面板標題在同一張畫面
/// 跟 `NotConnectedView` 的「還沒接上」互相矛盾。
///
/// 窮盡定義域（`Reason.allCases × MountOwner.allCases` ＋ connected 的
/// `MountOwner × Verification` ＋ 兩個頂層 case，型別推導、不寫數字，沿用
/// `InstallStateAllCases`——`OptionsMenuModelTests`／`PanelModelConnectCTATests` 既有用法）：
/// 對每一種**非** `connected` 的 `InstallState`，`TooltipText.text` 與 `PanelModel.title`
/// 都不得等於「connected 時的字串」，且彼此必須一致（同一個 oracle：`healthLabel`）。
@Suite("Tooltip 與面板標題窮盡一致（S0-2，T11 commit2）")
struct TooltipAndTitleConsistencyTests {

    /// 「connected 時的字串」的具體反例：liveCount/attentionCount 皆 0 時
    /// `TooltipText.sessionSummary` 回的句子——正是 S0-2 原本被誤用在非 connected 狀態的那句。
    static let emptyAppearance = AppearancePolicy.appearance(for: .empty)
    static let connectedEmptyText = "沒有活著的 session"

    @Test("前提：sessionSummary(.empty) 恰為「沒有活著的 session」（否則下面的反例字串就選錯了）")
    func precondition_sessionSummaryOfEmptyIsTheConnectedString() {
        #expect(TooltipText.sessionSummary(Self.emptyAppearance, language: .traditionalChinese) == Self.connectedEmptyText)
    }

    @Test("每一種非 connected InstallState：tooltip／面板標題都不等於 connected 字串，且彼此一致（等於 healthLabel）")
    func nonConnectedStatesNeverClaimConnectedText() {
        for install in InstallStateAllCases.all() {
            guard !isConnected(install) else { continue }

            let tooltip = TooltipText.text(appearance: Self.emptyAppearance, install: install,
                                           language: .traditionalChinese)
            let model = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                        install: install, version: "1.0", optionsExpanded: false,
                                        launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, language: .traditionalChinese)

            #expect(tooltip != Self.connectedEmptyText, """
                \(install) 的 tooltip 是「\(tooltip)」—— 不得等於 connected 時的字串
                「\(Self.connectedEmptyText)」（D-e：這正是 S0-2 的原始 bug，沒裝 hook 卻說有 session 資訊）
                """)
            #expect(model.title != Self.connectedEmptyText, """
                \(install) 的面板標題是「\(model.title)」—— 不得等於 connected 時的字串
                「\(Self.connectedEmptyText)」（同一顆根因的第二個表面：面板標題與 NotConnectedView 互相矛盾）
                """)
            #expect(tooltip == install.healthLabel(.traditionalChinese), "\(install) 的 tooltip 應等於 healthLabel「\(install.healthLabel(.traditionalChinese))」，實際「\(tooltip)」")
            #expect(model.title == install.healthLabel(.traditionalChinese), "\(install) 的面板標題應等於 healthLabel「\(install.healthLabel(.traditionalChinese))」，實際「\(model.title)」")
            #expect(tooltip == model.title, "\(install) 的 tooltip「\(tooltip)」與面板標題「\(model.title)」不一致 —— 同一張畫面不能有兩個答案")
        }
    }

    @Test("每一種 connected InstallState：tooltip 走 session 計數（sessionSummary），不是 healthLabel")
    func connectedStatesUseSessionSummaryNotHealthLabel() {
        for owner in MountOwner.allCases {
            for verified in Verification.allCases {
                let install = InstallState.connected(owner: owner, verified: verified)
                let tooltip = TooltipText.text(appearance: Self.emptyAppearance, install: install,
                                           language: .traditionalChinese)
                #expect(tooltip == TooltipText.sessionSummary(Self.emptyAppearance, language: .traditionalChinese), """
                    connected(\(owner), \(verified)) 的 tooltip 應走 sessionSummary，實際「\(tooltip)」
                    """)
            }
        }
    }

    /// A11（T11 A9–A11 批次，team-lead 自查）：`connected` ＋ rows 空時，`title`（頂端，走
    /// session 計數句子）與 `emptyRowsMessage`（本體，`PanelView` 在 `rows.isEmpty` 時印的
    /// 那句）先前是同一個字面常數「沒有活著的 session」——同一張畫面說了兩次同一句話，
    /// S0-2 那族的殘留。body 也不得等於 tooltip（`connected` 時 tooltip == title，見
    /// `connectedStatesUseSessionSummaryNotHealthLabel`，所以只要 body != title 就自動
    /// 滿足 body != tooltip；這裡兩條都寫出來，直接對照斷言而非依賴遞移）。
    @Test("每一種 connected InstallState：rows 空時，本體訊息不得等於標題，也不得等於 tooltip")
    func emptyRowsMessageDoesNotDuplicateTitleOrTooltip() {
        for owner in MountOwner.allCases {
            for verified in Verification.allCases {
                let install = InstallState.connected(owner: owner, verified: verified)
                let model = PanelModel.make(icon: .empty, sessions: [], palette: .default,
                                            install: install, version: "1.0", optionsExpanded: false,
                                            launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, language: .traditionalChinese)
                let tooltip = TooltipText.text(appearance: Self.emptyAppearance, install: install,
                                           language: .traditionalChinese)

                #expect(model.emptyRowsMessage != model.title, """
                    connected(\(owner), \(verified)) ＋ rows 空：本體訊息「\(model.emptyRowsMessage)」
                    與標題「\(model.title)」相同 —— 同一張畫面說了兩次同一句話
                    """)
                #expect(model.emptyRowsMessage != tooltip, """
                    connected(\(owner), \(verified)) ＋ rows 空：本體訊息「\(model.emptyRowsMessage)」
                    與 tooltip「\(tooltip)」相同
                    """)
            }
        }
    }

    private func isConnected(_ install: InstallState) -> Bool {
        if case .connected = install { return true }
        return false
    }
}
