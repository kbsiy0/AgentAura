import Testing
import AuraCore
import Foundation

/// codex-support T08（CX22 model 半，spec §6.3／design r9 §3）：`PanelRow.agentLabel`
/// 的推導本身已由 `AgentThreadingTests`（T05）四段證明過——這裡補的是「透過
/// `PanelModel.make(...)` 這個唯一建構入口」那一段：新增的 `codex`／`codexSnippet`／
/// `codexPathRejection`（T08b，T07 review 回頭補的裂縫）三個欄位不干擾既有 rows 推導，
/// 且三個新欄位透傳不失真（同一個 sample 傳進去、原封不動讀得出來）。
///
/// 期望值一律寫字面 `"Codex"`，**不拿 `Agent.codex.label` 跟自己比**（gate 哲學：生產
/// 常數不能自己當自己的裁判，同 T04 review 的陷阱——`agentFlag` 改壞後拿產生器輸出跟
/// 產生器自己的常數比，兩邊一起變、斷言恆真）。
@Suite("PanelModel 帶 codex 狀態（CX22 model 半）")
struct CodexRowLabelTests {

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

    static func model(sessions: [SessionState], codex: CodexState, codexSnippet: String?,
                      codexPathRejection: CodexHookPathCheck.Rejection? = nil) -> PanelModel {
        PanelModel.make(icon: icon, sessions: sessions, palette: .default,
                        install: .notConnected, version: "1.0", optionsExpanded: false,
                        launchAtLogin: nil, externalTargetPath: nil, banner: nil,
                        systemReduceMotion: false, userReduceMotion: false, iconPlate: true,
                        iconShape: .ledStrip, language: .traditionalChinese,
                        codex: codex, codexSnippet: codexSnippet, codexPathRejection: codexPathRejection)
    }

    @Test("PanelModel.make 帶 codex 狀態不干擾既有 rows 推導：.codex 顯示字面 \"Codex\"，.claude 不顯示")
    func agentLabelSurvivesThroughPanelModelMake() {
        let model = Self.model(sessions: [Self.session("claude-1", agent: .claude),
                                           Self.session("codex-1", agent: .codex)],
                               codex: .unavailable, codexSnippet: nil)
        // `.first(where:)?.agentLabel` 是**鏈式** optional（Swift 自動壓平），不是
        // `Dictionary` 下標那種 `String??`——後者曾在這裡讓 `byID["claude-1"] == nil`
        // 恆假（鍵存在、值是 `.some(.none)`，跟外層 `.none` 不相等，T08 review 實測）。
        let claudeLabel = model.rows.first(where: { $0.id == "claude-1" })?.agentLabel
        let codexLabel = model.rows.first(where: { $0.id == "codex-1" })?.agentLabel
        #expect(claudeLabel == nil, "Claude 側的列不該顯示任何 agent 標籤，實際 \(String(describing: claudeLabel))")
        #expect(codexLabel == "Codex", "Codex 側的列應顯示字面 \"Codex\"（不是空、不是原始 rawValue），實際 \(String(describing: codexLabel))")
    }

    @Test("codex／codexSnippet 兩個新欄位透傳不失真：每個 CodexStateKind 的代表值都原封不動讀得出來")
    func codexFieldsPassThroughVerbatim() {
        for kind in CodexStateKind.allCases {
            for sample in CodexState.samples(kind) {
                let model = Self.model(sessions: [], codex: sample, codexSnippet: nil)
                #expect(model.codex == sample, "\(kind) 的代表值透過 PanelModel.make 後失真：\(model.codex)")
            }
        }
    }

    @Test("codexSnippet 透傳：nil 與非 nil 字串都原封不動讀得出來")
    func codexSnippetPassesThroughVerbatim() {
        #expect(Self.model(sessions: [], codex: .occupiedByOther, codexSnippet: nil).codexSnippet == nil)
        let snippet = "hook snippet literal"
        #expect(Self.model(sessions: [], codex: .occupiedByOther, codexSnippet: snippet).codexSnippet == snippet)
    }

    /// T08b：`codexPathRejection` 是橫跨 `.connectedStalePath`／`.occupiedByOther` 的行程常數
    /// （D-t），不是任何 `CodexState` case 自己的欄位——這裡逐 `RejectionKind` 代表值
    /// （含 `nil`）驗證它跟 `codex`／`codexSnippet` 一樣透過 `PanelModel.make` 原封不動。
    @Test("codexPathRejection 透傳：nil 與每個 RejectionKind 代表值都原封不動讀得出來")
    func codexPathRejectionPassesThroughVerbatim() {
        #expect(Self.model(sessions: [], codex: .connectedStalePath, codexSnippet: nil,
                           codexPathRejection: nil).codexPathRejection == nil)
        for kind in CodexHookPathCheck.RejectionKind.allCases {
            for sample in CodexHookPathCheck.Rejection.samples(kind) {
                let model = Self.model(sessions: [], codex: .connectedStalePath, codexSnippet: nil,
                                       codexPathRejection: sample)
                #expect(model.codexPathRejection == sample,
                        "\(kind) 的代表值透過 PanelModel.make 後失真：\(String(describing: model.codexPathRejection))")
            }
        }
    }
}
