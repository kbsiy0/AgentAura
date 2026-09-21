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
/// `PanelView(model:).body`：② 裸 `statusLabel` 命中數恰為 4（本情境的實測基準，
/// 任一處被改回就會少 1，變 3）；③ `install.healthLabel(l)` **不得**以裸葉節點單獨出現
/// （`healthLabel` 是 computed method 呼叫的回傳值，不是任何 stored property，不會被上面
/// 那個洩漏污染——這條斷言對洩漏完全免疫，任一處改回 `healthLabel` 就會讓這個字串首次
/// 出現）。標題那一處的**值**另由純函式層的 **CX50④** 守，這裡只驗證 view 真的把它畫出來。
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

    /// ①：footer——單獨渲染 `PanelFooterView`（避開 `PanelView.body` 的洩漏源），
    /// 組合字面 `"<statusLabel> · v<version>"` 恰好出現一次。
    @Test("① footer chip：組合字面 \"<statusLabel> · v<version>\" 恰好出現一次")
    func footerRendersComposite() {
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
    @Test("②③ 標題與 CTA 窄條：裸 statusLabel 命中恰為 4（本情境實測基準）且 healthLabel 不得單獨出現")
    func titleAndCTAReadStatusLabelNotHealthLabel() {
        let model = Self.model(rows: [Self.codexSession("x1")])
        let leaves = CodexSectionViewTests.leafStrings(PanelView(model: model, onAction: { _ in }).body)
        let label = model.statusLabel(model.language)
        let healthLabel = model.install.healthLabel(model.language)

        let labelCount = leaves.filter { $0 == label }.count
        #expect(labelCount == 4, """
            裸 statusLabel 文字在 PanelView(model:).body 應該恰好命中 4 次（2 次是
            CodexSectionView／PanelFooterView 洩漏 model.title 的既知底噪，另外 2 次
            才是標題與 CTA 窄條真的實例化）。任一處被改回 healthLabel 都會讓這個數字
            少 1（變 3）。實際命中 \(labelCount) 次。
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
