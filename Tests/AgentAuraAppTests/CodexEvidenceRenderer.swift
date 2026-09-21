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
    struct Scenario {
        let name: String
        let desc: String
        let make: (Language) -> PanelModel
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

    /// 11 個情境（10 個題項 + 「connectedStalePath 兩種 Rejection 都不給重新接上按鈕」拆兩張，
    /// 見 #10／#11：這兩張與 #6／#7 不是同一個 `CodexState`（#6/#7 是 `occupiedByOther`／
    /// `blockedByBundlePath`，#10/#11 是 `connectedStalePath`），沒有重疊可併）。
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
            // 7. P2：blockedByBundlePath(.unsupportedCharacter(" "))——文案指名是空白字元。
            Scenario(name: "07-blocked-unsupported-character",
                     desc: "P2：blockedByBundlePath(.unsupportedCharacter(\" \"))——文案指名是空白字元＋snippet（同源）＋「複製」按鈕") { lang in
                panel(sessions: [claude], install: connected,
                     codex: .blockedByBundlePath(.unsupportedCharacter(" ")), codexSnippet: Self.realSnippet,
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
            // 10. R-9：connectedStalePath，pathRejection==.mustMoveToApplications——不畫
            //     「重新接上」按鈕，換句解釋（不給按鈕的理由：按下去會先 disconnect 一份還在運作的檔）。
            Scenario(name: "10-stale-rejection-must-move-withholds-reconnect",
                     desc: "R-9：connectedStalePath，pathRejection==.mustMoveToApplications——不畫「重新接上」按鈕，換句解釋（與 #6 不同 state：這張是 connectedStalePath，#6 是 occupiedByOther）") { lang in
                panel(sessions: [claude], install: connected, codex: .connectedStalePath,
                     codexPathRejection: .mustMoveToApplications, language: lang, now: now)
            },
            // 11. R-9：同上，另一種 Rejection——CX36 兩種 Rejection 都驗過會不給按鈕，這裡兩種都留證據。
            Scenario(name: "11-stale-rejection-unsupported-character-withholds-reconnect",
                     desc: "R-9：connectedStalePath，pathRejection==.unsupportedCharacter(\" \")——同樣不畫「重新接上」按鈕，與 #10 同一句解釋（文案不預設成因）；與 #7 不同 state：這張是 connectedStalePath，#7 是 blockedByBundlePath") { lang in
                panel(sessions: [claude], install: connected, codex: .connectedStalePath,
                     codexPathRejection: .unsupportedCharacter(" "), language: lang, now: now)
            },
        ]
    }

    @Test("產出 11 組 Codex 面板情境 × 兩語言（.aqua）＋ INDEX.md")
    func renderCodexEvidence() throws {
        let dir = try Self.outputDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date()
        let all = scenarios(now: now)

        var index: [(file: String, desc: String)] = []
        for scenario in all {
            for (language, suffix) in [(Language.english, "en"), (.traditionalChinese, "zh")] {
                let image = try render(scenario.make(language))
                let file = "\(scenario.name)-\(suffix).png"
                try EvidenceRenderer.writePNG(image, to: dir.appendingPathComponent(file))
                index.append((file, scenario.desc))
            }
        }
        try writeIndex(dir: dir, entries: index)
        #expect(index.count == all.count * 2, "情境數 × 兩語言，應等於實際寫出的張數，實際 \(index.count)")
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

            | 檔名 | 情境（給 persona 看什麼） |
            |---|---|

            """
        for e in entries {
            md += "| `\(e.file)` | \(e.desc) |\n"
        }
        try md.write(to: dir.appendingPathComponent("INDEX.md"), atomically: true, encoding: .utf8)
    }
}
