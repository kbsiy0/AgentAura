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

    /// r1 review M1：函式名必須逐字等於 spec §6.3／DoD 帳本指名的 gate 名
    /// `codexTrustWarningIsDrawnWithClaudeRowsPresent`，否則 `--filter` 照文件驗收
    /// 會靜默 `No matching test cases were run`（exit 0）。
    ///
    /// 正向：面板上只有一列 **Claude** 的活 session 時，`.codexConnected` banner 仍然要
    /// 真的畫出來——這正是 persona r1 抓到的那一行：r12 的 `effectiveBanner` 只看
    /// `!rows.isEmpty` 就把它抹掉。
    ///
    /// 負向對照：面板上出現一列 **Codex** 的活 session 時，承諾已經兌現，banner 該退場——
    /// 真的被實例化進畫面樹的那一次不該再出現。**兩格合成一條斷言**（命中次數差恰為 1，
    /// 見上方 doc comment 為什麼不能各自獨立用 `.contains`）。
    @Test("Claude 列時 banner 真的畫出來、Codex 列時 banner 真的退場：兩者命中次數差恰為 1")
    func codexTrustWarningIsDrawnWithClaudeRowsPresent() {
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

    /// r1 review M5：舊版寫「`>= 1`」，但洩漏底噪本身已經是 2——這條斷言在算術上不可能失敗
    /// （`0 == 0 + 1` 為假，兩邊同時歸零也救不了它），且實測在 CX48① mutation（banner 確定
    /// 沒被畫出來）下這條仍然綠、只有差值那條紅，失敗訊息卻宣稱「實際 0 次」這件證明不了的事。
    /// **改成推導式底噪**（同 CX51② 的處方）：`model.version` 只會透過 `CodexSectionView.model`／
    /// `PanelFooterView.model` 兩個持有整份 `model` 的子 view 洩漏，不會被 `BannerView` 真的
    /// 實例化與否影響——用它的命中數當底噪，門檻變成「底噪 + 1」，兩者都推導自同一份實測，
    /// 不是憑空湊的數字。
    @Test("Claude 列時 banner 命中數恰為「模型洩漏底噪 + 1」（不是任意下限）")
    func codexTrustWarningIsDrawnWithClaudeRowsPresent_noiseFloor() {
        let model = Self.model(rows: [Self.session("c1", agent: .claude)])
        let leaves = CodexSectionViewTests.leafStrings(PanelView(model: model, onAction: { _ in }).body)
        let noise = leaves.filter { $0 == model.version }.count
        let bannerCount = leaves.filter { $0 == Self.bannerFullText }.count
        #expect(bannerCount == noise + 1, """
            只有 Claude 列時，banner 全文命中數應該恰為「模型洩漏底噪（\(noise)，由 model.version
            的命中數推導）+ 1（BannerView 真的被實例化）」，實際 \(bannerCount) 次。
            （r2 review n1：這裡假設 model.version 不會被畫面上任何真實 view 直接印出來，
            只透過 CodexSectionView／PanelFooterView 洩漏——若哪天 PanelView 開始直接畫版本號，
            這條會因無關理由變紅，那時候要重新推導底噪，不是回頭寫死數字）
            """)
    }
}
