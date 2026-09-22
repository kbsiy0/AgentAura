import AppKit
import Foundation
import SwiftUI
import Testing
import AuraCore
@testable import AgentAuraApp

/// Codex 面板離屏渲染證據圖，供 persona-tester 人眼評分（P1–P4，見
/// `docs/superpowers/plans/2026-09-18-codex-support-dod.md`「persona 硬下限」表）。
/// 沿用既有 `EvidenceRenderer`／`Phase2EvidenceRenderer` 的模式（env gate、`NSHostingView`
/// ＋ `OffscreenRender`，不是 `ImageRenderer`）——不是新機制，這裡不改任何生產碼，只呼叫
/// 既有 `PanelModel.make(...)` 組裝、渲**完整** `PanelView`（不是只有 `CodexSectionView`），
/// 讓 Claude 側說明與 Codex 列疊在同一畫面的真實比例對 persona 可見（P1）。輸出
/// `docs/evidence/codex/`，每個情境兩語言各一張（`-en.png`／`-zh.png`），只用 `.aqua`
/// 淺色——深淺對比不是這批圖要驗的維度，`INDEX.md` 有完整說明。
@MainActor
@Suite("Codex 面板離屏渲染證據圖（persona 用，env gate）",
      .enabled(if: ProcessInfo.processInfo.environment["AURA_RENDER_EVIDENCE"] == "1"))
struct CodexEvidenceRenderer {

    static func outputDirectory() throws -> URL {
        try EvidenceRenderer.outputDirectory().deletingLastPathComponent().appendingPathComponent("codex")
    }

    /// 真的產生器輸出，不是手寫字面（同 `CodexSectionViewTests.realSnippet` 的既有理由）。
    static let realSnippet = CodexHooksJSON.snippet(hookBinaryPath: "/Applications/AgentAura.app/Contents/PlugIns/aura-hook")

    /// S1-6（persona r1，`493e0bf` 修前基準）：#07 宣告 `.unsupportedCharacter(" ")`，
    /// 這裡餵真的含空白的路徑產生 snippet，讓「即使產得出來也沒有畫」這件事有意義
    /// （負向斷言必須餵正向輸入，同 spec plan §0／D-ad）。**T13l（D-w 落地後）**：
    /// `.blockedByBundlePath` 兩種 Rejection 現在都不給 snippet——這個常數繼續餵，
    /// 用來證明「產得出來」與「畫不畫得出來」是兩回事，不是留著沒用的舊字面。
    static let realSnippetWithSpace = CodexHooksJSON.snippet(hookBinaryPath: "/Users/someone/My Apps/AgentAura.app/Contents/PlugIns/aura-hook")

    func session(_ id: String, _ name: String, _ a: Activity, agent: Agent, updatedAt: Date) -> SessionState {
        SessionState(id: id, projectName: name, permissionMode: "default", effort: nil, model: nil, agent: agent,
                    activity: a, mainActivity: a, subActivity: nil, currentTool: "Bash", subagentTool: nil,
                    toolDurationMs: nil, turnStartedAt: nil, subagents: [:], toolFailures: 0,
                    lastMessage: nil, errorType: nil, toolError: nil, liveness: .alive(pid: 1), updatedAt: updatedAt)
    }

    /// 只用 `.aqua`——沒有真 `NSWindow` 時 `.borderless` label 的顏色不可信（CLAUDE.md 第 5
    /// 條），這批圖要驗的是版面與文案，不是深淺對比，見 `writeIndex` 寫進 `INDEX.md` 的說明。
    func render(_ model: PanelModel) throws -> CGImage {
        let hosting = NSHostingView(rootView: PanelView(model: model, onAction: { _ in }))
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: max(hosting.fittingSize.height, 44))
        let bitmap = try OffscreenRender.render(hosting, over: .white)
        guard let image = bitmap.context.makeImage() else { throw OffscreenRender.SampleError.noData }
        return image
    }

    /// 一個情境＝一個「換語言重建」的工廠 ＋ 給 persona-tester 看的說明句（寫進 `INDEX.md`）。
    /// `languages`：預設兩語言各一張；#14（最壞高度組合）team-lead 指定只要英文一張
    /// （CX56 量到的最壞語言），故留一個縮小定義域的口子，不必為它硬湊一張沒人要看的中文重複圖。
    struct Scenario {
        let name: String
        let desc: String
        let languages: [Language]
        let make: (Language) -> PanelModel

        init(name: String, desc: String, languages: [Language] = [.english, .traditionalChinese],
            make: @escaping (Language) -> PanelModel) {
            self.name = name
            self.desc = desc
            self.languages = languages
            self.make = make
        }
    }

    /// 共用組裝——`icon` 從 `sessions` 推導（取最高優先序活動，同 `IconState` 既有語意），
    /// 其餘欄位給合理預設，只讓每個情境改真正要驗的那幾個參數。
    func panel(sessions: [SessionState] = [], install: InstallState, optionsExpanded: Bool = false,
              launchAtLogin: Bool? = true, banner: PanelBanner? = nil, codex: CodexState,
              codexSnippet: String? = nil, codexPathRejection: CodexHookPathCheck.Rejection? = nil,
              language: Language, now: Date) -> PanelModel {
        let icon: IconState
        if let top = sessions.map(\.activity).max(by: { $0.priority < $1.priority }) {
            var counts: [Activity: Int] = [:]
            for s in sessions { counts[s.activity, default: 0] += 1 }
            icon = IconState(activity: top, counts: counts, liveCount: sessions.count)
        } else {
            icon = .empty
        }
        return PanelModel.make(icon: icon, sessions: sessions, palette: .default, install: install,
                               version: "1.4.2", optionsExpanded: optionsExpanded, launchAtLogin: launchAtLogin,
                               externalTargetPath: nil, banner: banner, systemReduceMotion: false,
                               userReduceMotion: false, iconPlate: true, iconShape: .ledStrip, language: language,
                               codex: codex, codexSnippet: codexSnippet, codexPathRejection: codexPathRejection, now: now)
    }

    /// 15 個情境（原 12 個 `493e0bf` 基準 + T13l 三個新增）：10 個題項 + 「connectedStalePath
    /// 兩種 Rejection 都不給重新接上按鈕」拆兩張見 #10／#11（這兩張與 #6／#7 不是同一個
    /// `CodexState`，#6/#7 是 `occupiedByOther`／`blockedByBundlePath`，#10/#11 是
    /// `connectedStalePath`，沒有重疊可併）+ #12（S1-7 缺口）+ **T13l 新增**：#13／#13b
    /// （D-v 修後對照組，S0-1）＋ #14（最壞高度組合，D-ab／CX56）。
    func scenarios(now: Date) -> [Scenario] {
        let claude = session("a", "fitness-tracker", .working, agent: .claude, updatedAt: now)
        let codexRow = session("b", "fitness-tracker", .waiting, agent: .codex, updatedAt: now.addingTimeInterval(-30))
        let connected = InstallState.connected(owner: .thisApp, verified: .verified)

        return [
            // 1. D-j：~/.codex 不存在——完整面板（含一個活著的 Claude session）完全看不到任何 Codex 字樣。
            Scenario(name: "01-unavailable",
                     desc: "P1／D-j：~/.codex 不存在——完整面板（含活著的 Claude session）完全看不到任何 Codex 字樣") { lang in
                panel(sessions: [claude], install: connected, codex: .unavailable, language: lang, now: now)
            },
            // 2. P1：Claude 大版說明 ＋ Codex 單行提示 ＋ Options「接上 Codex」列同時出現。
            Scenario(name: "02-notConnected-options-expanded",
                     desc: "P1：Claude 大版說明＋Codex 卡片單行提示＋Options「接上 Codex」列同時出現，30 秒內看得出兩顆按鈕分屬哪個 agent") { lang in
                panel(install: .notConnected, optionsExpanded: true, codex: .notConnected, language: lang, now: now)
            },
            // 3. P3：接上成功 banner——兩句都在。rows 刻意留空：`.connected` kind banner 在有
            //    session 時會自動退場（A7），留空才能讓這張圖真的證明兩句都畫得出來。
            Scenario(name: "03-connected-banner",
                     desc: "P3：接上成功 banner——「下一個 Codex session 起生效」與「Codex 會問一次是否信任」兩句都在（rows 刻意留空——A7：.connected banner 有 session 時會自動退場，見 INDEX 附註）") { lang in
                panel(install: connected, banner: .codexConnected(language: lang), codex: .connected, language: lang, now: now)
            },
            // 4. connectedStalePath，pathRejection == nil：「App 移動過」＋「重新接上 Codex」。
            Scenario(name: "04-connected-stale-path",
                     desc: "connectedStalePath，pathRejection==nil——「App 移動過」提示＋「重新接上 Codex」按鈕") { lang in
                panel(sessions: [claude], install: connected, codex: .connectedStalePath, language: lang, now: now)
            },
            // 5. P2：occupiedByOther，snippet 有——說明＋可複製 snippet（與產生器同源）＋複製鈕。
            Scenario(name: "05-occupied-with-snippet",
                     desc: "P2：occupiedByOther，codexSnippet!=nil——說明＋可複製 snippet（與 CodexHooksJSON.snippet 同源）＋「複製」按鈕") { lang in
                panel(sessions: [claude], install: connected, codex: .occupiedByOther,
                     codexSnippet: Self.realSnippet, language: lang, now: now)
            },
            // 6. P2／R-10：occupiedByOther，pathRejection==.mustMoveToApplications——不給
            //    snippet，改說先把 App 移到應用程式。
            Scenario(name: "06-occupied-must-move-no-snippet",
                     desc: "P2／R-10：occupiedByOther，pathRejection==.mustMoveToApplications——不給 snippet／複製鈕，改說先把 App 移到「應用程式」") { lang in
                panel(sessions: [claude], install: connected, codex: .occupiedByOther,
                     codexPathRejection: .mustMoveToApplications, language: lang, now: now)
            },
            // 7. P2／S0-2（D-w，r13 後）：blockedByBundlePath(.unsupportedCharacter(" "))——
            //    文案指名是空白字元＋出路句，**不給 snippet**（餵真的含空白路徑產的
            //    `realSnippetWithSpace` 是負向斷言的正向輸入：證明「產得出來」但沒有畫）。
            Scenario(name: "07-blocked-unsupported-character",
                     desc: "P2／S0-2 修後（D-w）：blockedByBundlePath(.unsupportedCharacter(\" \"))——文案指名是空白字元＋出路句（把 App 移到不含該字元的位置）。**不給 snippet／複製鈕**——即使餵進去的是真的含空白路徑產生的 snippet（`realSnippetWithSpace`）也不畫，修前（`493e0bf`）這格會畫出那條會壞的路徑並給「複製」") { lang in
                panel(sessions: [claude], install: connected,
                     codex: .blockedByBundlePath(.unsupportedCharacter(" ")), codexSnippet: Self.realSnippetWithSpace,
                     codexPathRejection: .unsupportedCharacter(" "), language: lang, now: now)
            },
            // 8. 斷開成功 banner（codexDisconnected）＋斷開後卡片回到 notConnected 的提示。
            Scenario(name: "08-disconnected-banner",
                     desc: "斷開成功 banner（codexDisconnected，kind=.disconnected，不會像 #3 那樣因為有 session 而自動退場）＋斷開後 Codex 卡片回到 notConnected 的「接上 Codex」提示") { lang in
                panel(sessions: [claude], install: connected, banner: .codexDisconnected(language: lang),
                     codex: .notConnected, language: lang, now: now)
            },
            // 9. P4：同一份 sessions 列表裡 Claude 列與帶「Codex」標籤的列並存。
            Scenario(name: "09-mixed-claude-codex-rows",
                     desc: "P4：同一份 sessions 列表裡 Claude 列與帶「Codex」標籤的列並存，分得出來、列高不變（見 CodexRowLabelRenderTests 的既有像素／高度守衛）") { lang in
                panel(sessions: [claude, codexRow], install: connected, codex: .connected, language: lang, now: now)
            },
            // 10. R-9／S2-1（D-x，r13 後）：connectedStalePath，pathRejection==
            //     .mustMoveToApplications——不畫「重新接上」按鈕；開場句改成中性事實
            //     （不再說「下次開機就會消失」），成因／出路重用 D-w 那組。
            Scenario(name: "10-stale-rejection-must-move-withholds-reconnect",
                     desc: "R-9／S2-1 修後（D-x）：connectedStalePath，pathRejection==.mustMoveToApplications——不畫「重新接上」按鈕；開場句改成中性事實（只講「這份設定指向另一個位置」，不再宣稱「下次開機就會消失」），成因／出路沿用「把 App 移到『應用程式』」（與 #6 不同 state：這張是 connectedStalePath，#6 是 occupiedByOther）") { lang in
                panel(sessions: [claude], install: connected, codex: .connectedStalePath,
                     codexPathRejection: .mustMoveToApplications, language: lang, now: now)
            },
            // 11. R-9／S2-1（D-x，r13 後）：同上，另一種 Rejection——**修前 `493e0bf` 這兩張
            //     位元組完全相同**（persona r1 現場驗過），D-x 拆開中性開場＋依 rejection
            //     分流的成因／出路之後，這張與 #10 不再相同：指名字元＋不同的出路句。
            Scenario(name: "11-stale-rejection-unsupported-character-withholds-reconnect",
                     desc: "R-9／S2-1 修後（D-x）：connectedStalePath，pathRejection==.unsupportedCharacter(\" \")——同樣不畫「重新接上」按鈕，但**不再與 #10 位元組相同**：同一句中性開場之後接的是指名空白字元＋「把 App 移到不含該字元的位置」，不是 #10 的「移到『應用程式』」（修前 `493e0bf` 這兩張是同一張圖，可查證為假的「會消失」子句已拿掉；與 #7 不同 state：這張是 connectedStalePath，#7 是 blockedByBundlePath）") { lang in
                panel(sessions: [claude], install: connected, codex: .connectedStalePath,
                     codexPathRejection: .unsupportedCharacter(" "), language: lang, now: now)
            },
            // 12. S1-1 修後（D-y，r13 後）：本 change 的頭號情境——Claude 側
            //     `.notConnected`，同時有一列活著的 Codex session（agent==.codex，working
            //     態）。修前（`493e0bf`）標題／footer chip／CTA 窄條三處逐字都是「還沒接上」；
            //     修後三處改讀共用的 `PanelModel.statusLabel(_:)`——Codex 子句在前、Claude
            //     半句在後（例：英文「Codex connected · Claude Code: Not connected yet」）。
            Scenario(name: "12-notConnected-claude-with-live-codex-session",
                     desc: "S1-1 修後（D-y）：install=.notConnected（Claude 未接上）＋一列活著的 Codex session（working）＋Codex 卡片 .connected——標題／footer chip／CTA 窄條三處現在都讀 `statusLabel`，寫成「Codex connected · Claude Code: Not connected yet」（Codex 子句在前，見 §3.1），不再是修前（`493e0bf`）三處逐字「還沒接上」") { lang in
                let liveCodexSession = session("c", "fitness-tracker", .working, agent: .codex, updatedAt: now)
                return panel(sessions: [liveCodexSession], install: .notConnected, codex: .connected,
                            language: lang, now: now)
            },
            // 13. S0-1 修後對照組之一（D-v）：`.codexConnected` banner ＋ rows 含一列
            //     **Claude** session——banner 必須仍然出現。修前（`493e0bf` 的 #03）這張圖
            //     的 rows 必須留空才看得到兩句話，因為 `.codexConnected` 當時共用
            //     `.connected` 的退場條件（出現任何一列就退場）；修後 `.codexConnected` 只
            //     在出現 **Codex** 的列時才退場，一列 Claude session 對它什麼都不兌現。
            Scenario(name: "13-codexConnected-banner-persists-with-claude-row",
                     desc: "S0-1 修後（D-v）：.codexConnected banner ＋ rows 含一列 Claude session——banner 仍然出現（兩句話都在）。這是 #03（修前要 rows 留空才看得到兩句話）的直接對照：同一顆 banner 現在能與一列 Claude session 共存，因為退場條件改成看 hasCodexRow，不是看 rows.isEmpty") { lang in
                panel(sessions: [claude], install: connected, banner: .codexConnected(language: lang),
                     codex: .connected, language: lang, now: now)
            },
            // 13b. 對照組之二：同一顆 banner ＋ rows 含一列 **Codex** session——banner 應該
            //      已經退場（hasCodexRow==true，「下一個 Codex session 起生效」的承諾已兌現）。
            //      與 #13 並列，佐證退場條件是「看是不是 Codex 的列」，不是「rows 非空就不退場」。
            Scenario(name: "13b-codexConnected-banner-retires-with-codex-row",
                     desc: "對照（D-v）：.codexConnected banner ＋ rows 含一列 Codex session——banner 已退場（hasCodexRow==true，承諾已兌現）。與 #13 一起看：#13 有 Claude 列仍顯示 banner，這張有 Codex 列就不顯示，證明退場條件是「有沒有 Codex 的列」不是「rows 是否非空」") { lang in
                let codexOnly = session("d", "fitness-tracker", .working, agent: .codex, updatedAt: now)
                return panel(sessions: [codexOnly], install: connected, banner: .codexConnected(language: lang),
                            codex: .connected, language: lang, now: now)
            },
            // 14. S1-4／CX56（D-ab）最壞高度組合——與 CX56 的 `install` 代表值同一個
            //     （`.broken(.targetMissing, owner: .external)`，量出來的 `.replaceExternal`
            //     仿射代表值，見 `CodexSnippetHeightTests.installCandidates`）＋
            //     `.occupiedByOther` 有 snippet ＋ banner=.codexConnected ＋ rows 空 ＋
            //     英文（team-lead／CX56 都選英文：全域量測裡最壞的語言）。只產一張
            //     （`languages: [.english]`）——中文版沒有新增資訊，不必為了「兩語言各一張」
            //     的慣例硬湊。
            Scenario(name: "14-worst-height-combination",
                     desc: "S1-4／CX56 最壞高度組合（D-ab）：install=.broken(.targetMissing, owner:.external)（CX56 的 `.replaceExternal` 代表值）＋ .occupiedByOther 有 snippet ＋ banner=.codexConnected ＋ rows 空 ＋ 英文——固定高度＋可捲的 snippet 區塊落地後，天花板應 ≤780pt（@2x 1560px），「複製」鈕與 footer 都在畫面內。**只有這張圖是英文單張**（CX56 量到的最壞語言，中文版無新增資訊）",
                     languages: [.english]) { lang in
                panel(install: .broken(.targetMissing, owner: .external), banner: .codexConnected(language: lang),
                     codex: .occupiedByOther, codexSnippet: Self.realSnippet, language: lang, now: now)
            },
        ]
    }

    @Test("產出 15 組 Codex 面板情境（14 組兩語言 + #14 英文單張）（.aqua）＋ INDEX.md")
    func renderCodexEvidence() throws {
        let dir = try Self.outputDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date()
        let all = scenarios(now: now)

        var index: [(file: String, desc: String)] = []
        for scenario in all {
            for (language, suffix) in [(Language.english, "en"), (.traditionalChinese, "zh")]
                where scenario.languages.contains(language) {
                let image = try render(scenario.make(language))
                let file = "\(scenario.name)-\(suffix).png"
                try EvidenceRenderer.writePNG(image, to: dir.appendingPathComponent(file))
                index.append((file, scenario.desc))
            }
        }
        try writeIndex(dir: dir, entries: index)
        let expected = all.reduce(0) { $0 + $1.languages.count }
        #expect(index.count == expected, "每個情境的語言數加總，應等於實際寫出的張數，實際 \(index.count)，預期 \(expected)")
    }

    func writeIndex(dir: URL, entries: [(file: String, desc: String)]) throws {
        var md = """
            # Codex 面板離屏渲染證據圖（persona 用）

            由 `Tests/AgentAuraAppTests/CodexEvidenceRenderer.swift` 產出（觸發方式：\
            `AURA_RENDER_EVIDENCE=1 swift test --filter renderCodexEvidence`，同既有 `Phase2EvidenceRenderer`／\
            `VisualLandedEvidenceRenderer` 的 env gate 慣例）。每張都是**完整面板**（`PanelView`），\
            不是只有 `CodexSectionView`——讓 Claude 側說明與 Codex 列疊在同一畫面的真實比例可見（P1）。

            **尺寸單位**：這批圖是 @2x（Retina）點陣圖，寬 760px（面板邏輯寬度 380pt × 2，高度依內容而定）。\
            生產型別（`PanelModel`／`preferredContentSize` 等）內的高度數字單位是 pt，不是這批圖的 px——\
            兩者混用會誤判（CLAUDE.md「這個 codebase 的 gate 哲學」第 7 條）。

            **文字顏色不可信，版面與文案可信**：離屏渲染沒有真 `NSWindow`／key window，`.borderless` 按鈕與部分\
            label 落在次要前景色，不代表真 app 裡的實際顏色（CLAUDE.md 第 5 條）；只用這批圖核對「有沒有畫出正確的\
            字」「按鈕在不在」「版面有沒有被擠壓／裁切」，不要拿顏色深淺當證據。

            **只有 `.aqua`（淺色）**：深淺色對比不是這批圖要驗的維度，版面與文案在深淺模式下走同一份 SwiftUI\
            語意色（`.primary`／`.secondary`），需要深色對照時另外要求即可。

            ## persona r1 指出的視覺問題對照（T13l：全部補上「修後」欄）

            - **S0-1（D-v）** ↔ 修前 `03-connected-banner-*`（rows 刻意留空才看得到兩句話）→\
            **修後** `13-codexConnected-banner-persists-with-claude-row-*`（rows 有一列 **Claude**\
            session，banner 仍然出現）＋ `13b-codexConnected-banner-retires-with-codex-row-*`（rows 有一列\
            **Codex** session，banner 已退場，對照組）。退場條件從「rows 非空就退場」改成「出現 Codex 的列\
            （`hasCodexRow`）才退場」。
            - **S0-2（D-w）** ↔ 修前 `07-blocked-unsupported-character-*`（給 snippet＋「複製」）→\
            **修後同檔名**（本次重渲）：`.unsupportedCharacter` 現在**不給 snippet**，只給指名字元的解釋＋\
            出路句——即使餵進去的是真的含空白路徑產的 snippet 也沒有畫（`realSnippetWithSpace` 這條輸入常數\
            繼續留著，證明的是「產得出來」與「畫不畫」是兩回事）。
            - **S1-1（D-y）** ↔ 修前 `12-notConnected-claude-with-live-codex-session-*`（標題／footer chip／\
            CTA 窄條三處逐字「還沒接上」）→ **修後同檔名**（本次重渲）：三處現在讀 `statusLabel`，\
            寫成「Codex connected · Claude Code: Not connected yet」（Codex 子句在前）。
            - **S1-3（D-aa）** ↔ 修前 `05-occupied-with-snippet-*`（只有說明＋snippet＋「複製」，沒有合併\
            指示）→ **修後同檔名**（本次重渲）：多一行合併指示（「把這些 entry 併進你現有的 hooks 物件，\
            不要整份取代」）＋一顆「教我怎麼做」按鈕（送出既有 `.openHelp`）。
            - **S1-4（D-ab）** ↔ 修前 `05-occupied-with-snippet-*` ／ `07-blocked-unsupported-character-*`\
            （面板高度約 944pt，「複製」按鈕落在約 848pt 處，皆為 pt，非這批圖的 px）→ **修後**\
            `14-worst-height-combination-en`：snippet 區塊固定高度＋可捲，天花板 ≤780pt，「複製」鈕與 footer\
            都在畫面內（實測數字見檔名列表那一行）。**這張用的是 CX56 同一個 `install` 代表值\
            （`.broken(.targetMissing, owner: .external)`）與同一個天花板，不是另外挑的數字**。
            - **S2-1（D-x）** ↔ 修前 `10-*` ／ `11-*`（persona r1 現場驗過兩張位元組完全相同）→\
            **修後同檔名**（本次重渲）：兩張**不再相同**——中性開場句共用，但成因／出路依 rejection 分流\
            （#10 講「移到『應用程式』」，#11 指名字元並講「移到不含該字元的位置」）。
            - **S1-6（D-ad）** ↔ `07-blocked-unsupported-character-*`：證據渲染器本身的修正——snippet 輸入\
            改用真的含空白的路徑（`493e0bf` 已修，本次無變動）。
            - **S1-7（D-ad）** ↔ `12-notConnected-claude-with-live-codex-session-*`：新增證據圖本身\
            （`493e0bf` 已加，本次重渲內容因 D-y 落地而更新，見上面 S1-1 那條）。

            | 檔名 | 情境（給 persona 看什麼） |
            |---|---|

            """
        for e in entries {
            md += "| `\(e.file)` | \(e.desc) |\n"
        }
        try md.write(to: dir.appendingPathComponent("INDEX.md"), atomically: true, encoding: .utf8)
    }
}
