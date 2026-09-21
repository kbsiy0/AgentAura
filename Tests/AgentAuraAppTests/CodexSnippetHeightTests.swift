import Testing
import AppKit
import SwiftUI
@testable import AgentAuraApp
import AuraCore

/// **CX56 `snippetCardFitsOnA13InchScreen`**（D-ab，T13i）：修前 `CodexSectionView` 的
/// snippet 區塊沒有高度上限也沒有 `ScrollView`（persona r1 S1-4，實測 944pt），
/// 13 吋機顯示 Dock 時可用高度約 850pt——唯一的「複製」鈕與整個 footer 被裁在畫面外。
///
/// **定義域是五個維度的乘積**（全部程式推導，`optionsExpanded == false`）：
/// `CodexStateKind.allCases.flatMap(CodexState.samples)`（14 個代表值）× `Language.allCases`
/// （2）× `rows ∈ {空, 3 列}`（2）× `install ∈ {.connected, 一個由 T13i 實測選出的非 connected
/// 代表值}`（2，見 `CodexSnippetHeightMeasurement` STEP2：測過四種 `ConnectAffordance`，
/// `.replaceExternal` 最高）× `banner ∈ {nil, .codexConnected}`（2）＝ 224 格。
/// `install`／`banner` 兩維是 r14 review 補的——r13 的域漏了這兩維，persona 量到的 944pt
/// 出自兩張都是 `install: connected` 的證據圖，最壞組合（整版 CTA／窄條 ＋ 有 snippet 的卡片
/// ＋ 尚未退場的 banner）從來沒被量過。
///
/// **語意前置條件（N1）**：`PanelBanner.Kind.codexConnected` 已存在（T13b／`91760c4`
/// cherry-pick 進本 worktree）、`effectiveBanner` 已依 kind 分流——否則 `banner` 那一維
/// 量到的是假的（`.codexConnected` 在那之前仍是 `kind: .connected`，rows 非空時會被
/// `effectiveBanner` 吃掉）。
@MainActor
@Suite("Codex snippet 卡片的高度天花板與下限（CX56，T13i／D-ab）", .serialized)
struct CodexSnippetHeightTests {

    static let hookPath = AppDelegate.productionHookBinaryPath()
    static let ceiling: CGFloat = 780

    func session(_ id: String, _ a: Activity) -> SessionState {
        SessionState(id: id, projectName: id,
                    permissionMode: nil, effort: nil, model: nil,
                    activity: a, mainActivity: a, subActivity: nil,
                    currentTool: "Bash", subagentTool: nil, toolDurationMs: nil,
                    turnStartedAt: nil, subagents: [:], toolFailures: 0,
                    lastMessage: nil, errorType: nil, toolError: nil,
                    liveness: .alive(pid: 1), updatedAt: Date())
    }

    /// 同生產碼 `withheldSnippet` 的判準（R-10／D-w）：`.blockedByBundlePath(r)` → 扣住、
    /// pathRejection=r；`.occupiedByOther` → 真的產生器輸出、pathRejection=nil；其餘皆 nil。
    func codexInputs(for state: CodexState) -> (snippet: String?, rejection: CodexHookPathCheck.Rejection?) {
        switch state {
        case .blockedByBundlePath(let r): return (nil, r)
        case .occupiedByOther: return (CodexHooksJSON.snippet(hookBinaryPath: Self.hookPath), nil)
        default: return (nil, nil)
        }
    }

    func model(codex: CodexState, language: Language, sessionCount: Int,
              install: InstallState, banner: PanelBanner?, optionsExpanded: Bool = false) -> PanelModel {
        let (snippet, rejection) = codexInputs(for: codex)
        let icon = sessionCount == 0 ? IconState.empty : IconState(activity: .working, counts: [.working: sessionCount], liveCount: sessionCount)
        let sessions = (0..<sessionCount).map { session("s\($0)", .working) }
        // `.replaceExternal` 的副標（mountTargetNote）只在 externalTargetPath != nil 才出現
        // （PanelModel+ConnectCTA.swift:41-44）——量測要給真的路徑，否則量到假的（矮）高度。
        let target = install.affordance == .replaceExternal ? "/Applications/OtherApp.app" : nil
        return PanelModel.make(icon: icon, sessions: sessions, palette: .default,
                               install: install, version: "1.4.2", optionsExpanded: optionsExpanded,
                               launchAtLogin: true, externalTargetPath: target, banner: banner,
                               systemReduceMotion: false, userReduceMotion: false, iconPlate: true,
                               iconShape: .ledStrip, language: language, codex: codex,
                               codexSnippet: snippet, codexPathRejection: rejection)
    }

    func height(_ m: PanelModel) -> CGFloat {
        let controller = StatusItemController()
        defer { controller.removeFromStatusBar() }
        controller.setPanel(m)
        return controller.hostingController?.preferredContentSize.height ?? -1
    }

    static let allCodexStates: [CodexState] = CodexStateKind.allCases.flatMap(CodexState.samples)

    /// **grep 過**（`Sources/AuraCore/InstallAffordance.swift:23`）：`ConnectAffordance` 的
    /// 四個 case 是 `.connect`／`.replaceExternal`／`.explainOnly(Reason?)`／`.none`。
    /// **T13i 實測**（`CodexSnippetHeightMeasurement` STEP2，2026-09-21）：在最高的
    /// `CodexState`（`.occupiedByOther`，STEP1 確認）下，rows=3 時 `.replaceExternal`
    /// （1450pt）＞ `.connect`（1444pt）＞ `.explainOnly`／`.none`（皆 1402pt）——
    /// `.replaceExternal` 釘成 CX56 的 `install` 非 connected代表值。
    static let installCandidates: [(String, InstallState)] = [
        ("connected", .connected(owner: .thisApp, verified: .verified)),
        ("replaceExternal", .broken(.targetMissing, owner: .external)),
    ]

    /// 五維乘積的每一格：`preferredContentSize.height` 不得超過 780pt。
    @Test("CX56①：五維乘積（224 格）preferredContentSize.height ≤ 780pt")
    func heightWithinCeilingAcrossFullDomain() {
        var violations: [String] = []
        for state in Self.allCodexStates {
            for language in Language.allCases {
                for sessionCount in [0, 3] {
                    for (installLabel, install) in Self.installCandidates {
                        for (bannerLabel, banner) in [("nil", Optional<PanelBanner>.none), ("codexConnected", PanelBanner.codexConnected(language: language))] {
                            let m = model(codex: state, language: language, sessionCount: sessionCount, install: install, banner: banner)
                            let h = height(m)
                            if h > Self.ceiling {
                                violations.append("codex=\(state) lang=\(language) rows=\(sessionCount) install=\(installLabel) banner=\(bannerLabel) -> \(h)pt")
                            }
                        }
                    }
                }
            }
        }
        #expect(violations.isEmpty, """
            以下組合超過 780pt 天花板（紅掉時第一個問題是「面板是不是又長高了」，見 §4.10）：
            \(violations.joined(separator: "\n"))
            """)
    }

    /// 只在真的有 snippet 的那一態（`.occupiedByOther`，`pathRejection == nil`）檢查按鈕位置——
    /// 其餘態沒有 snippet 也沒有「複製」按鈕。按鈕身份用點擊辨識，不用陣列索引
    /// （`FooterPositionStabilityTests` 的既有手法與踩過的坑：橋接順序不等於宣告順序）。
    @Test("CX56②：.occupiedByOther 有 snippet 時，「複製」與 footer 按鈕的 minY 都在天花板內")
    func buttonsWithinCeilingWhenSnippetShown() throws {
        var violations: [String] = []
        for language in Language.allCases {
            for sessionCount in [0, 3] {
                for (installLabel, install) in Self.installCandidates {
                    for (bannerLabel, banner) in [("nil", Optional<PanelBanner>.none), ("codexConnected", PanelBanner.codexConnected(language: language))] {
                        let m = model(codex: .occupiedByOther, language: language, sessionCount: sessionCount, install: install, banner: banner)
                        let label = "lang=\(language) rows=\(sessionCount) install=\(installLabel) banner=\(bannerLabel)"
                        let controller = StatusItemController()
                        defer { controller.removeFromStatusBar() }
                        var lastReceived: [PanelAction] = []
                        controller.onAction = { lastReceived.append($0) }
                        controller.setPanel(m)
                        guard let hc = controller.hostingController else {
                            violations.append("\(label): hostingController 是 nil")
                            continue
                        }
                        let naturalHeight = hc.preferredContentSize.height
                        hc.view.frame = NSRect(x: 0, y: 0, width: 380, height: naturalHeight)
                        hc.view.layoutSubtreeIfNeeded()
                        _ = try OffscreenRender.render(hc.view, over: .white)

                        var copyY: CGFloat?
                        var toggleOptionsY: CGFloat?
                        for button in Self.allButtons(in: hc.view) {
                            lastReceived.removeAll()
                            button.performClick(nil)
                            if lastReceived == [.copyCodexSnippet] {
                                copyY = button.convert(button.bounds, to: hc.view).minY
                            } else if lastReceived == [.toggleOptions] {
                                toggleOptionsY = button.convert(button.bounds, to: hc.view).minY
                            }
                        }
                        guard let cy = copyY else {
                            violations.append("\(label): 點遍所有按鈕都沒有觸發 .copyCodexSnippet —— 「複製」按鈕不見了")
                            continue
                        }
                        guard let fy = toggleOptionsY else {
                            violations.append("\(label): 點遍所有按鈕都沒有觸發 .toggleOptions —— footer 按鈕不見了")
                            continue
                        }
                        if cy >= Self.ceiling {
                            violations.append("\(label): 複製按鈕 minY=\(cy)pt ≥ \(Self.ceiling)pt")
                        }
                        if fy >= Self.ceiling {
                            violations.append("\(label): footer 按鈕 minY=\(fy)pt ≥ \(Self.ceiling)pt")
                        }
                    }
                }
            }
        }
        #expect(violations.isEmpty, "以下組合按鈕落在天花板外或找不到：\n\(violations.joined(separator: "\n"))")
    }

    /// D-ab 下限：snippet 區塊高度不得低於「6 個視覺列」——這一格的基準由本 gate 在 App 層
    /// 渲一段 6 行等寬文字量出來（r15／n4：不得進 AuraCore，那層量不了文字），
    /// 且與 `CodexSnippetSizing` 上限用的行高是**同一個**量到的值（r16／n6）。
    @Test("CX56③：snippet 區塊高度不得低於 6 個視覺列")
    func snippetBlockMeetsMinimumVisibleLines() {
        let sixLines = Array(repeating: "X", count: CodexSnippetSizing.minVisibleLines).joined(separator: "\n")
        let hosting = NSHostingView(rootView:
            Text(sixLines).font(.system(size: 10, design: .monospaced)).padding(8))
        hosting.frame = NSRect(x: 0, y: 0, width: 360, height: 2000)
        let sixLineHeight = hosting.fittingSize.height
        #expect(CodexSnippetSizing.height >= sixLineHeight, """
            CodexSnippetSizing.height=\(CodexSnippetSizing.height)pt 低於真實渲染 6 行的高度\
            \(sixLineHeight)pt —— snippet 區塊比 6 個視覺列還矮
            """)
    }

    private static func allButtons(in view: NSView) -> [NSButton] {
        var found: [NSButton] = []
        if let button = view as? NSButton { found.append(button) }
        for sub in view.subviews { found.append(contentsOf: allButtons(in: sub)) }
        return found
    }
}
