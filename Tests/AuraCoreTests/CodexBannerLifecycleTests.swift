import Testing
import AuraCore
import Foundation

/// T13b（S0-1，D-v，CX47）：`.codexConnected` banner 自己的退場條件——A7 的既有退場條件
/// 「出現任何一列就退場」是為 Claude banner 推導的，直接沿用到 Codex 上不成立：出現一列
/// **Claude** 的 session 對「Codex 會問你一次是否信任」這句話什麼都沒兌現（persona r1 S0-1）。
///
/// 定義域走 `PanelBanner.Kind.allCases`（本 gate 是它的第一個消費者）× 四種列組合
/// （程式推導，不手列）：空／只有 Claude 列／只有 Codex 列／兩者都有。
@Suite("`.codexConnected` banner 自己的退場條件（CX47）")
struct CodexBannerLifecycleTests {

    static let icon = IconState(activity: .working, counts: [.working: 1], liveCount: 1)

    static func session(_ id: String, agent: Agent) -> SessionState {
        SessionState(id: id, projectName: id,
                    permissionMode: nil, effort: nil, model: nil, agent: agent,
                    activity: .working, mainActivity: .working, subActivity: nil,
                    currentTool: "Bash", subagentTool: nil, toolDurationMs: nil,
                    turnStartedAt: nil, subagents: [:], toolFailures: 0,
                    lastMessage: nil, errorType: nil, toolError: nil,
                    liveness: .alive(pid: 1), updatedAt: Date())
    }

    /// 四種列組合，程式推導：2 個 agent（`Agent.allCases`）的冪集合 = 2^2 = 4 種，不是手列的
    /// 魔術數字——`.empty` 對應空集合、`.onlyClaude`／`.onlyCodex` 對應單元素子集、`.both` 對應全集。
    enum RowCombo: CaseIterable {
        case empty, onlyClaude, onlyCodex, both

        var sessions: [SessionState] {
            switch self {
            case .empty: return []
            case .onlyClaude: return [CodexBannerLifecycleTests.session("c1", agent: .claude)]
            case .onlyCodex: return [CodexBannerLifecycleTests.session("x1", agent: .codex)]
            case .both: return [CodexBannerLifecycleTests.session("c1", agent: .claude),
                                CodexBannerLifecycleTests.session("x1", agent: .codex)]
            }
        }
    }

    /// 窮盡 switch，**不得有 `default`**——`Kind` 新增 case 時這裡編不過，逼你同時決定
    /// 這個代表值該退場還是不該退場（同 `CodexState.samples` 的既有理由）。
    static func banner(for kind: PanelBanner.Kind) -> PanelBanner {
        switch kind {
        case .connected: return .connected(language: .english)
        case .alreadyConnected: return .alreadyConnected(target: nil, language: .english)
        case .disconnected: return .disconnected(language: .english)
        case .error: return .error("boom")
        case .codexConnected: return .codexConnected(language: .english)
        }
    }

    static func model(kind: PanelBanner.Kind, combo: RowCombo) -> PanelModel {
        PanelModel.make(icon: icon, sessions: combo.sessions, palette: .default,
                        install: .notConnected, version: "1.0", optionsExpanded: false,
                        launchAtLogin: nil, externalTargetPath: nil, banner: banner(for: kind),
                        systemReduceMotion: false, userReduceMotion: false, iconPlate: true,
                        iconShape: .ledStrip, language: .english,
                        codex: .unavailable, codexSnippet: nil, codexPathRejection: nil)
    }

    /// r1 review M1：函式名必須逐字等於 spec §6.3／DoD 帳本指名的 gate 名，否則
    /// `swift test --filter codexConnectedBannerOnlyRetiresOnCodexRow` 照文件驗收會
    /// `No matching test cases were run`（exit 0）靜默拿到假綠燈。
    @Test("`.connected` 只在 rows 非空時退場；`.codexConnected` 只在出現 Codex 列時退場；其餘 kind 在每一種列組合下都不退場",
          arguments: PanelBanner.Kind.allCases, RowCombo.allCases)
    func codexConnectedBannerOnlyRetiresOnCodexRow(kind: PanelBanner.Kind, combo: RowCombo) {
        let model = Self.model(kind: kind, combo: combo)
        switch kind {
        case .connected:
            let expectRetired = !combo.sessions.isEmpty
            #expect((model.effectiveBanner == nil) == expectRetired, """
                .connected banner 在列組合 \(combo) 應該\(expectRetired ? "" : "不")退場，
                實際 effectiveBanner = \(String(describing: model.effectiveBanner))
                """)
        case .codexConnected:
            let expectRetired = model.hasCodexRow
            #expect((model.effectiveBanner == nil) == expectRetired, """
                .codexConnected banner 在列組合 \(combo) 應該\(expectRetired ? "" : "不")退場
                （只在出現 Codex 的列時），實際 effectiveBanner = \(String(describing: model.effectiveBanner))
                """)
        case .alreadyConnected, .disconnected, .error:
            #expect(model.effectiveBanner != nil, """
                .\(kind) banner 在列組合 \(combo) 不該有自動退場條件，實際卻被清成 nil
                """)
        }
    }

    /// 另加一格（r15 spec 明列）：只有 Claude 列時 `hasCodexRow` 必須是 `false`——否則
    /// `.codexConnected` 的退場條件仍然等價於 `!rows.isEmpty`，這條 gate 會在一個
    /// 壞掉的實作上全綠（`agentLabel != nil` 那個等價 mutant，見 mutation②）。
    ///
    /// r1 review m6／r2 review N1：**這一格是承重牆，不是補充**——`codexConnectedBannerOnlyRetiresOnCodexRow`
    /// 上面那條主測試的期望值 `expectRetired = model.hasCodexRow` 是自我指涉（跟 `hasCodexRow`
    /// 自己的定義比對）；實測把 `hasCodexRow` 改成 `!rows.isEmpty`（＝ mutation②的鏡像）餵回
    /// 主測試，20 個 test case **全綠**——只有這裡才會紅。**N1**：光靠 doc comment 講「只有這裡
    /// 才會紅」不夠——`swift test --filter codexConnectedBannerOnlyRetiresOnCodexRow` 原本只抓到
    /// 上面那條自我指涉的主測試（1 test），抓不到這一格；照文件驗收 CX47 這個 gate 名，會在
    /// `hasCodexRow` 壞掉時仍然回報 `1 test passed`、exit 0——**假綠燈搬到了隔壁**，M1 想解決的
    /// 問題沒有真的解決。函式名因此也加上 gate 名前綴（同其餘六個已改名的 gate同一個形狀），
    /// 讓 `--filter codexConnectedBannerOnlyRetiresOnCodexRow` 能同時抓到這一格。
    @Test("hasCodexRow：只有 Claude 列時必須是 false")
    func codexConnectedBannerOnlyRetiresOnCodexRow_2() {
        let model = Self.model(kind: .codexConnected, combo: .onlyClaude)
        #expect(model.hasCodexRow == false, """
            只有一列 Claude 的 session，hasCodexRow 應該是 false——否則 `.codexConnected`
            的退場條件仍然等價於 `!rows.isEmpty`，這條 gate 會在一個壞掉的實作上全綠
            """)
    }
}
