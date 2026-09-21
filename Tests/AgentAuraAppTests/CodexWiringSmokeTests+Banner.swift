import Testing
import Foundation
import SwiftUI
@testable import AgentAuraApp
import AuraCore

/// T13b（S0-1，D-v，CX48）：`.codexConnected` banner 的**渲染那一半**——CX24④ 斷言的是
/// `delegate.banner?.text`（**儲存值**），且那個 smoke 的 session graph 是空的，證明不了
/// 那兩句話真的被畫出來（persona r1 S0-1 就活在這個縫裡：面板上有任何一列時，
/// `effectiveBanner` 就把它抹掉）。這裡用既有的 `leafStrings(_:)`（`CodexSectionViewTests`，
/// `Mirror` 遞迴收 SwiftUI 值型別樹的 `String` 葉節點）掃**整個 `PanelView(model:).body`**，
/// 直接斷言渲染後的畫面有沒有那句 banner 全文——CX24④ 與這條是同一件事的兩層。
///
/// **實跑發現（寫這條 gate 時的必要前置調查）**：`.contains(...)` 對負向那格不成立——
/// `CodexSectionView`／`PanelFooterView` 兩個子 view 都把**整個** `model: PanelModel`
/// 存成自己的欄位（不是只存需要的欄位），`leafStrings` 遞迴 `Mirror` 時會把它們手上那份
/// `model.banner`（**原始欄位**，不是 `effectiveBanner`）也當成字串葉節點收進來——不管
/// `effectiveBanner` 有沒有正確判斷退場，那句 banner 全文都會透過這兩個子 view 的
/// `model` 欄位「漏」進 `leafStrings` 的結果恰好 2 次（實測：`banner: nil` 時 0 次、
/// `.codexConnected` 且**正確退場**時 2 次、`.codexConnected` 且**正確顯示**時 3 次）。
/// 這兩個「漏出來的」2 次跟 `effectiveBanner` 的判斷完全無關（不管退不退場都在），
/// 只有第 3 次（`BannerView` 真的被實例化進畫面樹）才是這條 gate 真正要問的訊號——
/// 直接 `.contains` 會讓負向那格在任何實作下都是「找得到」，恆真、測不出東西。
/// **改用「兩種列組合的命中次數差恰為 1」**：因為兩種列組合下 `model.banner` 欄位本身
/// 逐位元組相同（同一個 `.codexConnected(language:)` 呼叫），「漏出來的」2 次在兩邊完全
/// 相等而互相抵銷，差值只可能來自 `BannerView` 這個第三個來源真的有沒有被實例化——
/// 這正是 `effectiveBanner` 的退場判斷本身，不是子 view 的資料洩漏。
@MainActor
@Suite("`.codexConnected` banner 渲染後真的畫得出來（CX48）")
struct CodexWiringSmokeTestsBanner {

    static let bannerFullText = PanelBanner.codexConnected(language: .english).text

    static func model(rows: [SessionState]) -> PanelModel {
        PanelModel.make(icon: .empty, sessions: rows, palette: .default,
                        install: .notConnected, version: "1.0", optionsExpanded: false,
                        launchAtLogin: nil, externalTargetPath: nil,
                        banner: .codexConnected(language: .english),
                        systemReduceMotion: false, userReduceMotion: false, iconPlate: true,
                        iconShape: .ledStrip, language: .english,
                        codex: .connected, codexSnippet: nil, codexPathRejection: nil)
    }

    static func session(_ id: String, agent: Agent) -> SessionState {
        SessionState(id: id, projectName: id,
                    permissionMode: nil, effort: nil, model: nil, agent: agent,
                    activity: .working, mainActivity: .working, subActivity: nil,
                    currentTool: "Bash", subagentTool: nil, toolDurationMs: nil,
                    turnStartedAt: nil, subagents: [:], toolFailures: 0,
                    lastMessage: nil, errorType: nil, toolError: nil,
                    liveness: .alive(pid: 1), updatedAt: Date())
    }

    /// banner 全文在渲染後的 `PanelView(model:).body` 裡出現的次數（恰好比對，不是 `.contains`）。
    static func bannerOccurrenceCount(rows: [SessionState]) -> Int {
        let leaves = CodexSectionViewTests.leafStrings(PanelView(model: Self.model(rows: rows), onAction: { _ in }).body)
        return leaves.filter { $0 == Self.bannerFullText }.count
    }

    /// 正向：面板上只有一列 **Claude** 的活 session 時，`.codexConnected` banner 仍然要
    /// 真的畫出來——這正是 persona r1 抓到的那一行：r12 的 `effectiveBanner` 只看
    /// `!rows.isEmpty` 就把它抹掉。
    ///
    /// 負向對照：面板上出現一列 **Codex** 的活 session 時，承諾已經兌現，banner 該退場——
    /// 真的被實例化進畫面樹的那一次不該再出現。**兩格合成一條斷言**（命中次數差恰為 1，
    /// 見上方 doc comment 為什麼不能各自獨立用 `.contains`）。
    @Test("Claude 列時 banner 真的畫出來、Codex 列時 banner 真的退場：兩者命中次數差恰為 1")
    func drawnOnlyWhenClaudeRowsPresentNotCodexRows() {
        let withClaudeRow = Self.bannerOccurrenceCount(rows: [Self.session("c1", agent: .claude)])
        let withCodexRow = Self.bannerOccurrenceCount(rows: [Self.session("x1", agent: .codex)])
        #expect(withClaudeRow == withCodexRow + 1, """
            banner 全文在「只有 Claude 列」時的命中次數應該比「只有 Codex 列」時**恰好多 1**
            （多出來的那一次就是 `BannerView` 真的被實例化進畫面樹）：
            withClaudeRow=\(withClaudeRow)，withCodexRow=\(withCodexRow)。
            兩種列組合下 `model.banner` 欄位本身逐位元組相同，若這裡不是恰好差 1，
            代表 `.codexConnected` banner 沒有依 `hasCodexRow` 正確地只在出現 Codex 列時退場。
            """)
    }

    /// 額外的絕對值下限（防止兩邊都是 0 的退化情況讓上面那條「差 1」意外成立）：
    /// Claude 列那格至少要有一次命中，證明 banner 確實有被畫出來，不是兩邊都沒畫。
    @Test("Claude 列時 banner 至少出現一次（不是兩邊都沒畫，差值才有意義）")
    func drawnAtLeastOnceWithClaudeRows() {
        let withClaudeRow = Self.bannerOccurrenceCount(rows: [Self.session("c1", agent: .claude)])
        #expect(withClaudeRow >= 1, "只有 Claude 列時，banner 全文一次都沒出現在渲染後的畫面樹，實際 0 次")
    }
}
