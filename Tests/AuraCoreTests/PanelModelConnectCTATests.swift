import Testing
import AuraCore
import Foundation

/// G8(a)（spec §3.1.1／§3.3／§6.3）：model 層對每一種 `InstallState` 窮盡斷言
/// chip 文字、`showsConnectCTA`、CTA 文案、`connectCTAStyle`。
/// oracle 是 §3.1.1 的 affordance→CTA 表與 §3.3 的 chip 表。
/// (b)(c)（差異渲染、正向對照）是 T07 的工作，留在 `AgentAuraAppTests` 補在同一個 Gate 名字下。
@Suite("connectCTAIsModelDriven（G8a）")
struct PanelModelConnectCTATests {

    static let icon = IconState(activity: .idle, counts: [:], liveCount: 0)

    /// §3.3 的 chip 表——與 `InstallStateTests` 的 oracle 刻意分開抄一份：那條 gate 證明
    /// `healthLabel` 本身對不對，這條證明 `PanelModel.make` 有沒有把 `install` 原封不動地
    /// 帶到 model 上（tested ≠ wired）。兩份文字若之後漂移，兩條測試都會紅，不是只紅一條。
    static func expectedChipText(_ state: InstallState) -> String {
        switch state {
        case .claudeNotFound: return "找不到 Claude Code"
        case .notConnected: return "還沒接上"
        case .connected(let owner, let verified):
            // S2（T11 A9–A11 批次）：三個子句用「 · 」串接，owner 子句排在 verified 子句之前
            // ——見 `InstallAffordance.healthLabel(.traditionalChinese)`。
            let ownerClause = owner == .external ? " · 你的 repo 掛載" : ""
            switch verified {
            case .verified: return "已接上" + ownerClause
            case .inFlight: return "已接上" + ownerClause + " · 檢查中…"
            case .unknown, .blocked, .unconfirmed: return "已接上" + ownerClause + " · 未驗證"
            }
        case .broken(let reason, _):
            switch reason {
            case .targetMissing: return "接不上：App 被搬走了"
            case .targetUnresolvable: return "接不上：掛載解不開"
            case .notAPlugin: return "接不上：掛載內容不對"
            case .hookMissing: return "接不上：少了 hook 程式"
            case .hookNotExecutable: return "接不上：hook 沒有執行權限"
            case .hookBlockedOrBroken: return "接不上：macOS 擋住了 hook"
            case .hookUnconfirmed: return "接不上：無法確認 hook 能不能跑"
            case .occupiedByDirectory: return "已被其他安裝佔用"
            case .occupiedByFile: return "路徑被一個檔案佔住"
            }
        }
    }

    /// §3.1.1 的 affordance→CTA 表。
    static func expectedShowsConnectCTA(_ affordance: ConnectAffordance) -> Bool {
        switch affordance {
        case .connect, .replaceExternal: return true
        case .explainOnly, .none: return false
        }
    }

    static func expectedCTAText(_ affordance: ConnectAffordance) -> String? {
        switch affordance {
        case .connect: return "接上"
        case .replaceExternal: return "改指向這個 App"
        case .explainOnly, .none: return nil
        }
    }

    /// T07：`connectCTAAction`——CTA 按鈕實際送出的 `PanelAction`，與上面兩個文字 oracle
    /// 出自同一張 affordance 表（§3.1.1）。
    static func expectedCTAAction(_ affordance: ConnectAffordance) -> PanelAction? {
        switch affordance {
        case .connect: return .connect
        case .replaceExternal: return .replaceExternalMount
        case .explainOnly, .none: return nil
        }
    }

    static func model(for state: InstallState) -> PanelModel {
        PanelModel.make(icon: icon, sessions: [], palette: .default,
                        install: state, version: "1.0", optionsExpanded: false,
                        launchAtLogin: nil, externalTargetPath: nil, banner: nil, systemReduceMotion: false, userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: .traditionalChinese)
    }

    @Test("每一種 InstallState：chip 文字、showsConnectCTA、CTA 文案都對得上 oracle")
    func everyInstallStateMatchesOracle() {
        for state in InstallStateAllCases.all() {
            let model = Self.model(for: state)
            #expect(model.install.healthLabel(.traditionalChinese) == Self.expectedChipText(state), """
                \(state) 的 chip 文字對不上 §3.3 的表，實際 \(model.install.healthLabel(.traditionalChinese))
                """)
            #expect(model.showsConnectCTA == Self.expectedShowsConnectCTA(state.affordance), """
                \(state) 的 showsConnectCTA 對不上 §3.1.1 的表，實際 \(model.showsConnectCTA)
                """)
            #expect(model.connectCTAText == Self.expectedCTAText(state.affordance), """
                \(state) 的 CTA 文案對不上 §3.1.1 的表，實際 \(String(describing: model.connectCTAText))
                """)
            #expect(model.connectCTAAction == Self.expectedCTAAction(state.affordance), """
                \(state) 的 connectCTAAction 對不上 §3.1.1 的表，實際 \(String(describing: model.connectCTAAction))
                """)
        }
    }

    @Test("rows 空、無 banner 時：showsConnectCTA 為 true 的狀態 connectCTAStyle 必為 .fullPanel，否則 .none")
    func connectCTAStyleFollowsShowsConnectCTAWhenRowsEmpty() {
        for state in InstallStateAllCases.all() {
            let model = Self.model(for: state)
            let expected: CTAStyle = model.showsConnectCTA ? .fullPanel : .none
            #expect(model.connectCTAStyle == expected, """
                \(state) 的 connectCTAStyle 應為 \(expected)，實際 \(model.connectCTAStyle)
                """)
        }
    }
}
