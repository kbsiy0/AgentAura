import Testing
import Foundation
import SwiftUI
@testable import AgentAuraApp
import AuraCore

/// T13f（S1-1，D-y，CX51，r14 改方法）：`dualAgentStatusLabelReachesAllThreeSites`——
/// D-y 的接線層。情境：`install = .notConnected`＋`codex = .connected`＋
/// `rows = [一列 Codex 的活 session]`（＝ persona r1 的頭號情境，證據圖 #12）。
///
/// **r13 的寫法（「三處都 `contains(statusLabel)`」）對它自己宣告的三個 mutation 全部不紅**：
/// 三處渲染的是同一個字串，`leafStrings` 回的是扁平陣列，任一處改回 `install.healthLabel`
/// 之後另外兩處還在，`contains` 仍然成立。
///
/// **寫這條 gate 時的兩個必要前置調查（都有實跑數字，不是背景知識）**：
///
/// 1. **`CodexSectionView`／`PanelFooterView` 把整個 `model: PanelModel` 存成自己的欄位**
///    （同 CX48 doc comment 已經記過的同一個洩漏）：`Mirror` 遞迴會把它們手上那份
///    `model.title`（**原始欄位**，`install` 非 connected 時逐位元組等於 `statusLabel`，
///    CX50④ 保證）也當字串葉節點收進來——跟渲染對不對無關，只要 `model.banner` 非 nil
///    或 `model.title` 剛好等於某個要找的字串，就會被算進去。實測（本情境）：**裸
///    `statusLabel` 文字在 `PanelView(model:).body` 命中恰好 4 次**——2 次是上述洩漏
///    （`CodexSectionView.model.title` ＋ `PanelFooterView.model.title`），另外 2 次才是
///    真的被實例化的 `Text(model.title)`（標題）與 `ConnectCTABannerView(label:)`（CTA
///    窄條）。**不是 spec 草案寫的「2」**——那個數字沒有算進洩漏，本檔用實跑值。
///
///    **r1 review M3：這個 4 不得寫死**——多一個持有整份 `model` 的子 view，這個數字就會變，
///    跟「標題／CTA 有沒有正確接線」這個行為本身無關（CLAUDE.md gate 哲學 #2：每個數字要
///    推導）。改用 `model.version` 的命中數當**底噪**（`version` 只透過同一兩個子 view
///    洩漏，不受 `BannerView`／標題／CTA 接線正確與否影響，實測恰為 2），門檻變成
///    「底噪 + 2」。
/// 2. **`PanelFooterView` 原本的 `Text("\(...) · v\(...)")` 是字面插值，Swift 選中的是
///    `Text(LocalizedStringKey)` 多載，不是 `Text(String)`**——`LocalizedStringKey` 把
///    插值拆成「格式鍵＋參數」分開存放，`Mirror` 永遠掃不到組合後的完整字串（實測：
///    掃到的是 `"%@ · v%@"` 這個格式鍵本身，加上兩個參數分開的葉節點，**完全沒有**
///    `"<statusLabel> · v<version>"` 這個組合結果）。改成 `Text(verbatim:)`
///    （`PanelFooterView.swift`，T13f 同一個 commit）——這是語意上更正確的選擇（這串
///    文字是我們自己 L10n 系統算好的動態內容，不對應任何原生 `.strings` 表的鍵），
///    渲染像素不變，但只有這樣改，footer 的組合結果才可能出現在 `leafStrings` 的輸出裡。
///
/// **方法**：footer 的組合字面**改用 `PanelFooterView(model:).body` 單獨渲染**（不經過
/// `PanelView.body`，完全避開上述洩漏——`PanelFooterView` 自己不會巢狀另一個持有整份
/// `model` 的子 view）；標題／CTA 窄條這兩處合併用**兩條可分辨**的斷言守，都掃整個
/// `PanelView(model:).body`：② 裸 `statusLabel` 命中數恰為「底噪 + 2」（`noise` 由
/// `model.version` 的命中數推導，實測恰 2）；③ `install.healthLabel(l)` **不得**以裸葉節點
/// 單獨出現（`healthLabel` 是 computed method 呼叫的回傳值，不是任何 stored property，不會
/// 被上面那個洩漏污染——這條斷言對洩漏完全免疫，任一處改回 `healthLabel` 就會讓這個字串
/// 首次出現）。標題那一處的**值**另由純函式層的 **CX50④** 守，這裡只驗證 view 真的把它畫出來。
///
/// **兩種「改回」mutation 對 labelCount 的影響不同，實跑分別記錄**（r1 review m3 更正）：
/// ① 把 `PanelModel.swift` 的 `title(for:install:codex:language:)` 改回直接呼叫
/// `install.healthLabel(language)`（＝ CX50 mutation⑤，不經過共用 `statusLabel` 核心）——
/// `model.title` 這個**欄位本身**的值連同它的兩份洩漏都變成 `healthLabel`，於是
/// labelCount **4→1**（只剩 CTA 那一份還算 `statusLabel`），healthLabelCount 0→3，
/// 且 **CX50④ 也跟著紅**（`model.title` 真的不等於 `model.statusLabel` 了）。
/// ② 把 `PanelView.swift` 的 CTA 窄條 `label:` 參數改回 `model.install.healthLabel(...)`
/// （只動 view 層的讀取點，不動 `model.title` 本身）——只少真的被實例化的那一份，
/// labelCount **4→3**，healthLabelCount 0→1，**CX50④ 維持綠**（純函式層的
/// `model.title`／`model.statusLabel` 都沒被動到，兩者依然相等）。
@MainActor
@Suite("三處狀態字串真的接到 statusLabel（CX51）")
struct CodexWiringSmokeTestsDualAgentStatus {

    static func model(rows: [SessionState]) -> PanelModel {
        PanelModel.make(icon: .empty, sessions: rows, palette: .default,
                        install: .notConnected, version: "1.4.2", optionsExpanded: false,
                        launchAtLogin: nil, externalTargetPath: nil, banner: nil,
                        systemReduceMotion: false, userReduceMotion: false, iconPlate: true,
                        iconShape: .ledStrip, language: .english,
                        codex: .connected, codexSnippet: nil, codexPathRejection: nil)
    }

    static func codexSession(_ id: String) -> SessionState {
        SessionState(id: id, projectName: id,
                    permissionMode: nil, effort: nil, model: nil, agent: .codex,
                    activity: .working, mainActivity: .working, subActivity: nil,
                    currentTool: "Bash", subagentTool: nil, toolDurationMs: nil,
                    turnStartedAt: nil, subagents: [:], toolFailures: 0,
                    lastMessage: nil, errorType: nil, toolError: nil,
                    liveness: .alive(pid: 1), updatedAt: Date())
    }

    /// r1 review M1：gate 名 `dualAgentStatusLabelReachesAllThreeSites` 拆成 2 個
    /// `@Test`（footer 單獨渲染一條、標題＋CTA 合併一條），依 spec §6.3 慣例加 `_<條目>`。
    ///
    /// ①：footer——單獨渲染 `PanelFooterView`（避開 `PanelView.body` 的洩漏源），
    /// 組合字面 `"<statusLabel> · v<version>"` 恰好出現一次。
    @Test("① footer chip：組合字面 \"<statusLabel> · v<version>\" 恰好出現一次")
    func dualAgentStatusLabelReachesAllThreeSites_1() {
        let model = Self.model(rows: [Self.codexSession("x1")])
        let leaves = CodexSectionViewTests.leafStrings(PanelFooterView(model: model, onAction: { _ in }).body)
        let composite = "\(model.statusLabel(model.language)) · v\(model.version)"
        let count = leaves.filter { $0 == composite }.count
        #expect(count == 1, """
            footer 應該恰好畫出一次組合字面「\(composite)」，實際命中 \(count) 次。
            葉節點：\(leaves)
            """)
    }

    /// ②③ 合成一條：標題與 CTA 窄條是否真的接到 statusLabel／有沒有漏接改回 healthLabel。
    ///
    /// r1 review M3：`labelCount == 4` 原本是寫死的量測值，其中 2 是
    /// `CodexSectionView`／`PanelFooterView` 洩漏 `model.title` 的底噪（同 CX48 doc comment
    /// 記過的洩漏）——多一個持有整份 `model` 的子 view，這個數字就會變，跟「標題／CTA 有沒有
    /// 正確接線」這個行為本身無關。**改用 `model.version` 的命中數推導底噪**（`version` 只會
    /// 透過同一兩個子 view 洩漏，不會被 `BannerView`／標題／CTA 是否正確接線影響），門檻變成
    /// 「底噪 + 2」（標題 1 個真實例化 + CTA 1 個）。
    /// **另更正舊 doc comment的錯誤宣稱**：標題那一處被改回 `healthLabel` 時，實測是
    /// **4→1**（不是 4→3）——因為 `model.title` 這個**欄位本身**的值也會跟著變（它的計算
    /// 邏輯就是 `title(for:install:codex:language:)`，若把 `PanelView.swift` 的讀取點改回
    /// `install.healthLabel` 只影響「畫出來的那一個」，欄位洩漏的兩份仍然是舊值 `statusLabel`；
    /// 但若是把 `PanelModel.title` 的**計算邏輯本身**改回（CX50 mutation⑤），欄位值連同兩份
    /// 洩漏都會變成 `healthLabel`，於是原本算作 `statusLabel` 命中的洩漏兩份也消失，
    /// 4→1）；CTA 窄條被改回時欄位不受影響，只少真實例化那一份，是 4→3。兩種都在下面的
    /// mutation 表驗證過。
    @Test("②③ 標題與 CTA 窄條：裸 statusLabel 命中恰為「底噪 + 2」且 healthLabel 不得單獨出現")
    func dualAgentStatusLabelReachesAllThreeSites_2() {
        let model = Self.model(rows: [Self.codexSession("x1")])
        let leaves = CodexSectionViewTests.leafStrings(PanelView(model: model, onAction: { _ in }).body)
        let label = model.statusLabel(model.language)
        let healthLabel = model.install.healthLabel(model.language)

        let noise = leaves.filter { $0 == model.version }.count
        let labelCount = leaves.filter { $0 == label }.count
        #expect(labelCount == noise + 2, """
            裸 statusLabel 文字在 PanelView(model:).body 應該恰好命中「底噪（\(noise)，由
            model.version 的命中數推導）+ 2」（標題與 CTA 窄條各一次真的實例化）。
            實際命中 \(labelCount) 次。
            （r2 review n1：這裡假設 model.version 不會被畫面上任何真實 view 直接印出來，
            只透過 CodexSectionView／PanelFooterView 洩漏——若哪天 PanelView 開始直接畫版本號，
            這條會因無關理由變紅，那時候要重新推導底噪，不是回頭寫死數字）
            """)

        let healthLabelCount = leaves.filter { $0 == healthLabel }.count
        #expect(healthLabelCount == 0, """
            install.healthLabel（不含 Codex 子句的那句話）不該以裸葉節點單獨出現——
            這條斷言對 model 欄位洩漏免疫（healthLabel 是 computed method 呼叫的回傳值，
            不是 stored property）；一旦出現，代表標題或 CTA 窄條有一處被改回讀
            model.install.healthLabel 而不是 model.statusLabel。實際命中 \(healthLabelCount) 次。
            """)
    }
}
